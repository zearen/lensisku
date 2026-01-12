use std::collections::HashMap;
use std::sync::Mutex;
use actix_web::{web, App, HttpServer, HttpResponse, HttpRequest};
use once_cell::sync::Lazy;
use serde_json::Value;
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use sha2::Digest;
use openssl::sign::Verifier;
use openssl::pkey::PKey;
use openssl::x509::X509;

static CERT_CACHE: Lazy<Mutex<HashMap<String, String>>> = Lazy::new(|| {
    Mutex::new(HashMap::new())
});

#[derive(Debug, Clone)]
struct AppConfig {
    webhook_id: String,
    listen_port: u16,
    listen_path: String,
    cache_dir: String,
}

impl AppConfig {
    fn from_env() -> Self {
        dotenvy::dotenv().ok();
        
        Self {
            webhook_id: std::env::var("WEBHOOK_ID").expect("WEBHOOK_ID must be set"),
            listen_port: std::env::var("LISTEN_PORT")
                .unwrap_or_else(|_| "8080".to_string())
                .parse()
                .expect("LISTEN_PORT must be a valid number"),
            listen_path: std::env::var("LISTEN_PATH")
                .unwrap_or_else(|_| "/payments/webhook/paypal".to_string()),
            cache_dir: std::env::var("CACHE_DIR")
                .unwrap_or_else(|_| ".".to_string()),
        }
    }
}

async fn download_and_cache_cert(url: &str) -> Result<String, Box<dyn std::error::Error>> {
    let mut cache = CERT_CACHE.lock().unwrap();
    
    if let Some(cert) = cache.get(url) {
        return Ok(cert.clone());
    }

    if !url.starts_with("https://api.paypal.com/") {
        return Err("Invalid certificate URL".into());
    }

    let cert_pem = reqwest::get(url).await?.text().await?;
    
    // Validate certificate
    let cert = X509::from_pem(cert_pem.as_bytes())?;
    
    // Verify certificate time validity
    let now = openssl::asn1::Asn1Time::days_from_now(0)?;
    let not_before = cert.not_before();
    let not_after = cert.not_after();
    
    use std::cmp::Ordering;
    
    // Compare against not_before (cert shouldn't be used before this time)
    if let Ok(ordering) = now.compare(not_before) {
        if ordering == Ordering::Less {
            return Err("Certificate is not yet valid".into());
        }
    }
    
    // Compare against not_after (cert shouldn't be used after this time)
    if let Ok(ordering) = now.compare(not_after) {
        if ordering == Ordering::Greater {
            return Err("Certificate is expired".into());
        }
    }

    cache.insert(url.to_string(), cert_pem.clone());
    Ok(cert_pem)
}

async fn verify_signature(
    event: &[u8],
    headers: &actix_web::http::header::HeaderMap,
    webhook_id: &str,
) -> Result<bool, Box<dyn std::error::Error>> {
    tracing::info!("\nRust Implementation Debug:");
    tracing::info!("Raw event length: {}", event.len());
    tracing::info!("Raw event (first 100 chars): {}", String::from_utf8_lossy(&event[..event.len().min(100)]));

    let transmission_id = headers
        .get("paypal-transmission-id")
        .and_then(|v| v.to_str().ok())
        .ok_or("Missing transmission ID")?;
    let timestamp = headers
        .get("paypal-transmission-time")
        .and_then(|v| v.to_str().ok())
        .ok_or("Missing timestamp")?;
    let cert_url = headers
        .get("paypal-cert-url")
        .and_then(|v| v.to_str().ok())
        .ok_or("Missing cert URL")?;
    let signature_b64 = headers
        .get("paypal-transmission-sig")
        .and_then(|v| v.to_str().ok())
        .ok_or("Missing signature")?;

    tracing::info!("\nHeaders:");
    tracing::info!("Transmission ID: {}", transmission_id);
    tracing::info!("Timestamp: {}", timestamp);
    tracing::info!("Cert URL: {}", cert_url);
    tracing::info!("Signature (first 50): {}", &signature_b64[..50.min(signature_b64.len())]);
    tracing::info!("Webhook ID: {}", webhook_id);

    let crc = crc32fast::hash(event);
    tracing::info!("\nCRC32 Calculation:");
    tracing::info!("Raw CRC (hex): {:x}", crc);
    tracing::info!("CRC (decimal): {}", crc);

    let message = format!("{transmission_id}|{timestamp}|{webhook_id}|{crc}");
    tracing::info!("\nValidation message: {}", message);

    let cert_pem = download_and_cache_cert(cert_url).await?;
    tracing::info!("Certificate length: {}", cert_pem.len());

    let signature = BASE64.decode(signature_b64)?;
    tracing::info!("Decoded signature length: {}", signature.len());

    // Load the certificate and get the public key
    let cert = X509::from_pem(cert_pem.as_bytes())?;
    let public_key = cert.public_key()?;
    
    // Create and configure the verifier
    let mut verifier = Verifier::new(openssl::hash::MessageDigest::sha256(), &public_key)?;
    verifier.update(message.as_bytes())?;
    
    let result = verifier.verify(&signature)?;
    tracing::info!("\nSignature verification result: {}", result);

    Ok(result)
}

async fn handle_webhook(
    req: HttpRequest,
    payload: web::Bytes,
    config: web::Data<AppConfig>,
) -> HttpResponse {
    let headers = req.headers();
    
    match verify_signature(&payload, headers, &config.webhook_id).await {
        Ok(true) => {
            match serde_json::from_slice::<Value>(&payload) {
                Ok(event_data) => {
                    tracing::info!(
                        "Valid webhook received: {} {}",
                        event_data["id"].as_str().unwrap_or("unknown"),
                        event_data["event_type"].as_str().unwrap_or("unknown")
                    );
                    HttpResponse::Ok().finish()
                }
                Err(e) => {
                    tracing::error!("Failed to parse event JSON: {}", e);
                    HttpResponse::BadRequest().finish()
                }
            }
        }
        Ok(false) => {
            tracing::warn!("Invalid signature");
            HttpResponse::BadRequest().finish()
        }
        Err(e) => {
            tracing::error!("Verification error: {}", e);
            HttpResponse::InternalServerError().finish()
        }
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    tracing_subscriber::fmt::init();
    
    let config = AppConfig::from_env();
    let listen_path = config.listen_path.clone();
    let port = config.listen_port;
    
    tracing::info!("Starting server on port {}", port);
    tracing::info!("Webhook path: {}", listen_path);
    
    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(config.clone()))
            .service(
                web::resource(&listen_path)
                    .route(web::post().to(handle_webhook))
            )
    })
    .bind(("127.0.0.1", port))?
    .run()
    .await
}
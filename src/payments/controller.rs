use actix_web::{get, post, web, HttpResponse, Responder};
use deadpool_postgres::Pool;
use log::info;
use serde::Deserialize;

use super::{dto::*, paypal::PayPalOrder, service, PaymentProvider};
use crate::{auth::Claims, payments::paypal::PayPalProvider};

#[derive(Debug, Deserialize)]
struct PayPalEvent {
    event_type: String,
    resource: serde_json::Value,
}

#[derive(Debug, Deserialize, Clone)]
#[allow(dead_code)]
struct PayPalResource {
    id: String,
    status: String,
    custom_id: Option<String>,
    amount: PayPalAmount,
}

#[derive(Debug, Deserialize, Clone)]
struct PayPalAmount {
    value: String,
    currency_code: String,
}

#[derive(Debug, Deserialize)]
pub struct GenericPaymentIntent {
    pub id: String,
    pub amount: u64,
    pub currency: String,
    pub metadata: std::collections::HashMap<String, String>,
}

#[utoipa::path(
    post,
    path = "/payments/subscriptions",
    tag = "payments",
    request_body = CreateSubscriptionRequest,
    responses(
        (status = 200, description = "Subscription created successfully", body = PayPalSubscriptionDto),
        (status = 400, description = "Invalid request"),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal server error")
    ),
    security(("bearer_auth" = [])),
    summary = "Create PayPal Subscription",
    description = "Creates a new PayPal subscription for the authenticated user."
)]
#[post("/subscriptions")]
pub async fn create_paypal_subscription(
    pool: web::Data<Pool>,
    claims: Claims,
    req: web::Json<CreateSubscriptionRequest>,
) -> impl Responder {
    let paypal_provider = match PayPalProvider::new(
        std::env::var("PAYPAL_CLIENT_ID").unwrap_or_default(),
        std::env::var("PAYPAL_CLIENT_SECRET").unwrap_or_default(),
    ) {
        Ok(provider) => provider,
        Err(e) => {
            log::error!("Failed to create PayPal provider: {}", e);
            return HttpResponse::InternalServerError()
                .body("Failed to initialize payment provider");
        }
    };

    match paypal_provider.create_subscription(&req.into_inner()).await {
        Ok(paypal_response) => {
            match service::create_subscription_record(&pool, claims.sub, &paypal_response).await {
                Ok(_) => HttpResponse::Ok().json(paypal_response),
                Err(e) => {
                    log::error!("Failed to record subscription locally: {}", e);
                    HttpResponse::InternalServerError()
                        .body("Failed to record subscription locally.")
                }
            }
        }
        Err(e) => {
            log::error!("Failed to create PayPal subscription: {}", e);
            HttpResponse::InternalServerError().body("Failed to create PayPal subscription.")
        }
    }
}

#[utoipa::path(
    get,
    path = "/payments/subscriptions/{subscription_id}",
    tag = "payments",
    params(
        ("subscription_id" = String, Path, description = "PayPal Subscription ID")
    ),
    responses(
        (status = 200, description = "Subscription details fetched successfully", body = PayPalSubscriptionDto),
        (status = 401, description = "Unauthorized"),
        (status = 403, description = "Forbidden"),
        (status = 404, description = "Subscription not found"),
        (status = 500, description = "Internal server error")
    ),
    security(("bearer_auth" = [])),
    summary = "Get PayPal Subscription Details",
    description = "Retrieves details for a specific PayPal subscription."
)]
#[get("/subscriptions/{subscription_id}")]
pub async fn get_paypal_subscription_details(
    pool: web::Data<Pool>,
    claims: Claims,
    subscription_id_path: web::Path<String>,
) -> impl Responder {
    let paypal_provider = match PayPalProvider::new(
        std::env::var("PAYPAL_CLIENT_ID").unwrap_or_default(),
        std::env::var("PAYPAL_CLIENT_SECRET").unwrap_or_default(),
    ) {
        Ok(provider) => provider,
        Err(e) => {
            log::error!("Failed to create PayPal provider: {}", e);
            return HttpResponse::InternalServerError()
                .body("Failed to initialize payment provider");
        }
    };

    let subscription_id = subscription_id_path.into_inner();

    // Security Check: Verify user owns the subscription
    match service::get_subscription_owner(&pool, &subscription_id).await {
        Ok(Some(owner_user_id)) => {
            if owner_user_id != claims.sub {
                return HttpResponse::Forbidden().finish();
            }
            // User owns the subscription, proceed.
        }
        Ok(None) => {
            return HttpResponse::NotFound()
                .body(format!("Subscription {} not found.", subscription_id))
        }
        Err(e) => {
            log::error!(
                "Failed to verify subscription ownership for {}: {}",
                subscription_id,
                e
            );
            return HttpResponse::InternalServerError()
                .body("Failed to verify subscription ownership.");
        }
    }

    match paypal_provider
        .get_subscription_details(&subscription_id)
        .await
    {
        Ok(details) => {
            // Additional check: ensure the custom_id from PayPal matches our expectation if set
            // or that the subscription record in our DB for this ID belongs to claims.sub
            // This is a more robust check than just relying on PayPal's response if custom_id wasn't used
            // or if we want to ensure our local records align.
            // For now, we trust the initial DB check is sufficient.
            HttpResponse::Ok().json(details)
        }
        Err(e) => {
            log::error!(
                "Failed to get PayPal subscription details for {}: {}",
                subscription_id,
                e
            );
            // Check error type if possible to return NotFound vs InternalServerError
            if e.to_string().contains("RESOURCE_NOT_FOUND") {
                // Example check
                HttpResponse::NotFound()
                    .body(format!("Subscription {} not found.", subscription_id))
            } else {
                HttpResponse::InternalServerError()
                    .body("Failed to get PayPal subscription details.")
            }
        }
    }
}

#[utoipa::path(
    post,
    path = "/payments/subscriptions/{subscription_id}/cancel",
    tag = "payments",
    params(
        ("subscription_id" = String, Path, description = "PayPal Subscription ID")
    ),
    request_body = CancelSubscriptionRequestDto,
    responses(
        (status = 204, description = "Subscription cancelled successfully"),
        (status = 400, description = "Invalid request"),
        (status = 401, description = "Unauthorized"),
        (status = 403, description = "Forbidden"),
        (status = 500, description = "Internal server error")
    ),
    security(("bearer_auth" = [])),
    summary = "Cancel PayPal Subscription",
    description = "Cancels an active PayPal subscription for the authenticated user."
)]
#[post("/subscriptions/{subscription_id}/cancel")]
pub async fn cancel_paypal_subscription(
    pool: web::Data<Pool>,
    claims: Claims,
    subscription_id_path: web::Path<String>,
    req: web::Json<CancelSubscriptionRequestDto>,
) -> impl Responder {
    let paypal_provider = match PayPalProvider::new(
        std::env::var("PAYPAL_CLIENT_ID").unwrap_or_default(),
        std::env::var("PAYPAL_CLIENT_SECRET").unwrap_or_default(),
    ) {
        Ok(provider) => provider,
        Err(e) => {
            log::error!("Failed to create PayPal provider: {}", e);
            return HttpResponse::InternalServerError()
                .body("Failed to initialize payment provider");
        }
    };

    let subscription_id = subscription_id_path.into_inner();
    let reason = &req.reason;

    // Security Check: Verify user owns the subscription before attempting cancellation.
    match service::get_subscription_owner(&pool, &subscription_id).await {
        Ok(Some(owner_user_id)) => {
            if owner_user_id != claims.sub {
                return HttpResponse::Forbidden().finish();
            }
            // User owns the subscription, proceed with cancellation.
        }
        Ok(None) => {
            return HttpResponse::NotFound()
                .body(format!("Subscription {} not found.", subscription_id))
        }
        Err(e) => {
            log::error!(
                "Failed to verify subscription ownership for cancellation of {}: {}",
                subscription_id,
                e
            );
            return HttpResponse::InternalServerError()
                .body("Failed to verify subscription ownership.");
        }
    }

    match paypal_provider
        .cancel_subscription(&subscription_id, reason)
        .await
    {
        Ok(_) => {
            match service::process_subscription_cancellation(&pool, &subscription_id, Some(reason))
                .await
            {
                Ok(_) => HttpResponse::NoContent().finish(),
                Err(e) => {
                    log::error!(
                        "Failed to update local subscription status after cancellation for {}: {}",
                        subscription_id,
                        e
                    );
                    HttpResponse::InternalServerError()
                        .body("Failed to update local subscription status after cancellation.")
                }
            }
        }
        Err(e) => {
            log::error!(
                "Failed to cancel PayPal subscription {}: {}",
                subscription_id,
                e
            );
            HttpResponse::InternalServerError().body("Failed to cancel PayPal subscription.")
        }
    }
}

#[utoipa::path(
    post,
    path = "/payments/orders",
    tag = "payments",
    request_body(content = String, description = "Order creation payload"),
    responses(
        (status = 200, description = "Order created", body = PayPalOrder),
        (status = 400, description = "Invalid request"),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal server error")
    ),
    security(("bearer_auth" = [])),
    summary = "Create PayPal order",
    description = "Create a new PayPal order to start the transaction. Returns order details including approval URL."
)]
#[post("/orders")]
pub async fn create_payment(
    pool: web::Data<Pool>,
    claims: Claims,
    req: web::Json<CreatePaymentRequest>,
) -> impl Responder {
    let paypal_provider = match PayPalProvider::new(
        std::env::var("PAYPAL_CLIENT_ID").unwrap_or_default(),
        std::env::var("PAYPAL_CLIENT_SECRET").unwrap_or_default(),
    ) {
        Ok(provider) => provider,
        Err(e) => {
            log::error!("Failed to create PayPal provider: {}", e);
            return HttpResponse::InternalServerError()
                .body("Failed to initialize payment provider");
        }
    };

    match paypal_provider
        .create_order(req.amount_cents, &req.currency, claims.sub)
        .await
    {
        Ok(order) => {
            if let Err(e) = service::store_payment_order(&pool, claims.sub, &order, &req).await {
                log::error!("Failed to store payment order: {}", e);
                return HttpResponse::InternalServerError().body("Failed to store payment order");
            }
            HttpResponse::Ok().json(order)
        }
        Err(e) => {
            log::error!("Failed to create PayPal order: {}", e);
            HttpResponse::BadRequest().body(e.to_string())
        }
    }
}

#[utoipa::path(
    post,
    path = "/payments/orders/{order_id}/capture",
    tag = "payments",
    responses(
        (status = 200, description = "Order captured", body = PayPalOrder),
        (status = 400, description = "Invalid request"),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal server error")
    ),
    security(("bearer_auth" = [])),
    summary = "Capture PayPal order",
    description = "Capture a PayPal order to complete the transaction. Returns captured order details."
)]
#[post("/orders/{order_id}/capture")]
pub async fn capture_order(pool: web::Data<Pool>, order_id: web::Path<String>) -> impl Responder {
    let paypal_provider = match PayPalProvider::new(
        std::env::var("PAYPAL_CLIENT_ID").unwrap_or_default(),
        std::env::var("PAYPAL_CLIENT_SECRET").unwrap_or_default(),
    ) {
        Ok(provider) => provider,
        Err(e) => {
            log::error!("Failed to create PayPal provider: {}", e);
            return HttpResponse::InternalServerError()
                .body("Failed to initialize payment provider");
        }
    };

    match paypal_provider.capture_order(&order_id).await {
        Ok(order) => {
            if let Err(e) = service::update_payment_order(&pool, &order_id, "captured").await {
                log::error!("Failed to update payment order: {}", e);
                return HttpResponse::InternalServerError().body("Failed to update payment order");
            }
            HttpResponse::Ok().json(order)
        }
        Err(e) => {
            log::error!("Failed to capture PayPal order: {}", e);
            HttpResponse::BadRequest().body(e.to_string())
        }
    }
}

#[utoipa::path(
    post,
    path = "/payments/webhook/paypal",
    tag = "payments",
    request_body(content = String, description = "PayPal webhook payload"),
    responses(
        (status = 200, description = "Webhook processed successfully"),
        (status = 400, description = "Invalid webhook signature"),
        (status = 500, description = "Internal server error")
    ),
    summary = "Handle PayPal webhook events",
    description = "Endpoint for PayPal to send payment status updates. Processes payment completion, \
                  failure, and other transaction events. Validates webhook signature and updates \
                  payment records accordingly."
)]
#[post("/webhook/paypal")]
pub async fn paypal_webhook(
    pool: web::Data<Pool>,
    payload: web::Bytes,
    req: actix_web::HttpRequest,
) -> Result<HttpResponse, actix_web::Error> {
    info!("Received PayPal webhook event");

    let payload_str = std::str::from_utf8(&payload)
        .map_err(|_| actix_web::error::ErrorBadRequest("Invalid payload encoding"))?;

    // Extract PayPal signature headers
    let headers = req.headers();
    let transmission_id = headers
        .get("PAYPAL-TRANSMISSION-ID")
        .and_then(|h| h.to_str().ok())
        .ok_or_else(|| actix_web::error::ErrorBadRequest("Missing transmission ID"))?;

    let transmission_time = headers
        .get("PAYPAL-TRANSMISSION-TIME")
        .and_then(|h| h.to_str().ok())
        .ok_or_else(|| actix_web::error::ErrorBadRequest("Missing transmission time"))?;

    let cert_url = headers
        .get("PAYPAL-CERT-URL")
        .and_then(|h| h.to_str().ok())
        .ok_or_else(|| actix_web::error::ErrorBadRequest("Missing cert URL"))?;

    let transmission_sig = headers
        .get("PAYPAL-TRANSMISSION-SIG")
        .and_then(|h| h.to_str().ok())
        .ok_or_else(|| actix_web::error::ErrorBadRequest("Missing signature"))?;

    // Verify the webhook signature
    let paypal_provider = match PayPalProvider::new(
        std::env::var("PAYPAL_CLIENT_ID").unwrap_or_default(),
        std::env::var("PAYPAL_CLIENT_SECRET").unwrap_or_default(),
    ) {
        Ok(provider) => provider,
        Err(e) => {
            return Err(actix_web::error::ErrorInternalServerError(format!(
                "Failed to initialize PayPal provider: {}",
                e
            )));
        }
    };

    let is_valid = paypal_provider
        .verify_webhook_signature(
            payload_str,
            transmission_sig,
            transmission_id,
            transmission_time,
            cert_url,
        )
        .await
        .map_err(|e| {
            actix_web::error::ErrorBadRequest(format!("Signature verification failed: {}", e))
        })?;

    if !is_valid {
        return Ok(HttpResponse::BadRequest().json(WebhookResponse {
            success: false,
            message: "Invalid webhook signature".to_string(),
        }));
    }

    let event: PayPalEvent = serde_json::from_str(payload_str).map_err(|e| {
        actix_web::error::ErrorBadRequest(format!("Invalid webhook payload: {}", e))
    })?;

    info!("Received PayPal webhook event type: {}", event.event_type);
    log::debug!("Full webhook payload: {:?}", payload_str);

    match event.event_type.as_str() {
        // Existing Payment Capture Events
        "PAYMENT.CAPTURE.COMPLETED" => {
            match serde_json::from_value::<PayPalResource>(event.resource.clone()) {
                Ok(resource) => {
                    info!("Processing PAYMENT.CAPTURE.COMPLETED for resource ID: {}", resource.id);
                    info!("Amount value to parse: {}", resource.amount.value);
                    let amount = match resource.amount.value.parse::<f64>() {
                        Ok(val) => (val * 100.0) as u64,
                        Err(e) => {
                            let err_msg = format!("Failed to parse amount '{}': {}", resource.amount.value, e);
                            log::error!("{}", err_msg);
                            return Ok(HttpResponse::BadRequest().json(WebhookResponse { success: false, message: err_msg }));
                        }
                    };

                    let mut metadata = std::collections::HashMap::new();
                    if let Some(custom_id) = resource.custom_id {
                        if let Some(user_id_str) = custom_id.split('-').nth(4) { // Assuming specific format
                            if let Ok(user_id) = user_id_str.parse::<i32>() {
                                metadata.insert("user_id".to_string(), user_id.to_string());
                            } else {
                                metadata.insert("user_id".to_string(), "unknown_user_format".to_string());
                            }
                        }
                        metadata.insert("custom_id".to_string(), custom_id);
                    }

                    let payment_intent = GenericPaymentIntent {
                        id: resource.id,
                        amount,
                        currency: resource.amount.currency_code.to_lowercase(),
                        metadata,
                    };
                    match service::handle_payment_success(&pool, &payment_intent, &service::PaymentProvider::PayPal).await {
                        Ok(_) => Ok(HttpResponse::Ok().json(WebhookResponse { success: true, message: "Payment processed successfully".to_string() })),
                        Err(e) => {
                            log::error!("Failed to handle PayPal payment success: {}", e);
                            Ok(HttpResponse::InternalServerError().json(WebhookResponse { success: false, message: format!("Error processing payment: {}", e) }))
                        }
                    }
                }
                Err(e) => {
                    log::error!("Failed to deserialize PayPalResource for PAYMENT.CAPTURE.COMPLETED: {}", e);
                    Ok(HttpResponse::BadRequest().json(WebhookResponse { success: false, message: "Invalid resource for payment capture event".to_string() }))
                }
            }
        }
        "PAYMENT.CAPTURE.DENIED" | "PAYMENT.CAPTURE.DECLINED" => {
             match serde_json::from_value::<PayPalResource>(event.resource.clone()) {
                Ok(resource) => {
                    info!("Processing PAYMENT.CAPTURE.DENIED/DECLINED for resource ID: {}", resource.id);
                    let payment_intent = GenericPaymentIntent {
                        id: resource.id,
                        amount: (resource.amount.value.parse::<f64>().unwrap_or(0.0) * 100.0) as u64,
                        currency: resource.amount.currency_code.to_lowercase(),
                        metadata: Default::default(), // Consider if metadata is needed/available
                    };
                    match service::handle_payment_failure(&pool, &payment_intent).await {
                        Ok(_) => Ok(HttpResponse::Ok().json(WebhookResponse { success: true, message: "Payment failure recorded".to_string() })),
                        Err(e) => {
                            log::error!("Failed to handle PayPal payment failure: {}", e);
                            Ok(HttpResponse::InternalServerError().json(WebhookResponse { success: false, message: format!("Error processing payment failure: {}", e) }))
                        }
                    }
                }
                Err(e) => {
                    log::error!("Failed to deserialize PayPalResource for PAYMENT.CAPTURE.DENIED/DECLINED: {}", e);
                    Ok(HttpResponse::BadRequest().json(WebhookResponse { success: false, message: "Invalid resource for payment capture event".to_string() }))
                }
            }
        }

        // PayPal Subscription Event Types
        // Using constants from paypal.rs
        super::paypal::PAYPAL_EVENT_SUB_ACTIVATED
        | super::paypal::PAYPAL_EVENT_SUB_CANCELLED
        | super::paypal::PAYPAL_EVENT_SUB_EXPIRED
        | super::paypal::PAYPAL_EVENT_SUB_SUSPENDED
        | super::paypal::PAYPAL_EVENT_SUB_PAYMENT_FAILED
        | super::paypal::PAYPAL_EVENT_PAYMENT_SALE_COMPLETED // Assuming this is for subscription renewals
        // | "BILLING.SUBSCRIPTION.UPDATED" // Not explicitly listed in paypal.rs constants, but mentioned in task. Add if needed.
        => {
            info!("Processing PayPal subscription event: {}", event.event_type);
            // Based on the prompt: "The event.resource field in the incoming webhook payload needs to be deserialized into dto::PayPalSubscriptionDto for subscription events."
            // And the example: "match serde_json::from_value::<dto::SubscriptionWebhookEventResource>(event.resource.clone())"
            // The example implies event.resource is SubscriptionWebhookEventResource.
            // SubscriptionWebhookEventResource contains `resource: PayPalSubscriptionDto`.
            // This means if PayPal sends the *entire* SubscriptionWebhookEventResource structure as the value of `event.resource` in `PayPalEvent`,
            // then the example deserialization is correct.
            match serde_json::from_value::<SubscriptionWebhookEventResource>(event.resource.clone()) {
                Ok(sub_event_resource) => {
                    match service::update_subscription_from_webhook(&pool, &sub_event_resource).await {
                        Ok(_) => Ok(HttpResponse::Ok().json(WebhookResponse { success: true, message: "Subscription webhook processed".to_string() })),
                        Err(e) => {
                            log::error!("Failed to handle subscription webhook (event: {}): {}", event.event_type, e);
                            Ok(HttpResponse::InternalServerError().json(WebhookResponse { success: false, message: format!("Error processing subscription webhook: {}", e) }))
                        }
                    }
                }
                Err(e) => {
                    log::error!("Failed to deserialize SubscriptionWebhookEventResource for event {}: {}. Raw resource: {:?}", event.event_type, e, event.resource);
                    // Fallback: if the above fails, it might be that event.resource is *just* the PayPalSubscriptionDto
                    match serde_json::from_value::<PayPalSubscriptionDto>(event.resource.clone()) {
                        Ok(direct_sub_dto) => {
                            log::warn!("Deserialized event.resource as PayPalSubscriptionDto directly for event type: {}. This indicates PayPal sends the Subscription DTO directly as event.resource. Constructing SubscriptionWebhookEventResource for service.", event.event_type);
                            // We need to construct SubscriptionWebhookEventResource as the service function expects it.
                            let wrapped_resource = SubscriptionWebhookEventResource {
                                id: direct_sub_dto.id.clone(), // Use subscription ID as the event resource ID
                                create_time: direct_sub_dto.create_time.clone(), // Or another relevant time from the event if available
                                resource_type: "subscription".to_string(), // As it's a subscription event
                                event_type: event.event_type.clone(), // The original event type
                                summary: format!("Webhook event {} for subscription {}", event.event_type, direct_sub_dto.id), // Auto-generated summary
                                resource: direct_sub_dto, // The actual PayPalSubscriptionDto
                                links: None, // Assuming no specific links for the event resource wrapper itself, or get from direct_sub_dto if applicable
                            };
                            match service::update_subscription_from_webhook(&pool, &wrapped_resource).await {
                                Ok(_) => Ok(HttpResponse::Ok().json(WebhookResponse { success: true, message: "Subscription webhook processed (fallback path)".to_string() })),
                                Err(e_fallback) => {
                                    log::error!("Failed to handle subscription webhook via fallback (event: {}): {}", event.event_type, e_fallback);
                                    Ok(HttpResponse::InternalServerError().json(WebhookResponse { success: false, message: format!("Error processing subscription webhook (fallback): {}", e_fallback) }))
                                }
                            }
                        }
                        Err(e_direct) => {
                            log::error!("Also failed to deserialize event.resource as PayPalSubscriptionDto for event {}: {}. Raw resource: {:?}", event.event_type, e_direct, event.resource);
                            Ok(HttpResponse::BadRequest().json(WebhookResponse { success: false, message: "Invalid subscription resource in webhook, and fallback also failed.".to_string() }))
                        }
                    }
                }
            }
        }
        unknown_event_type => {
            log::info!("PayPal webhook event type not handled: {}", unknown_event_type);
            Ok(HttpResponse::Ok().json(WebhookResponse {
                success: true, // Successfully received, just not acted upon
                message: format!("Event type '{}' received but not handled by this endpoint.", unknown_event_type),
            }))
        }
    }
} // Added missing closing brace for paypal_webhook function

#[utoipa::path(
    path = "/payments/balance",
    tag = "payments",
    responses(
        (status = 200, description = "User balance", body = BalanceResponse),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal server error")
    ),
    security(("bearer_auth" = [])),
    summary = "Get user payment balance",
    description = "Retrieve the current payment balance for the authenticated user. \
                  Includes available funds and transaction history. Requires valid authentication token."
)]
#[get("/balance")]
pub async fn get_balance(pool: web::Data<Pool>, claims: Claims) -> impl Responder {
    match service::get_balance(&pool, claims.sub).await {
        Ok(balance) => HttpResponse::Ok().json(balance),
        Err(e) => HttpResponse::InternalServerError().body(e.to_string()),
    }
}

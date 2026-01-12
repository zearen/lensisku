use chrono::Datelike;
use lettre::{
    message::MultiPart,
    transport::smtp::{
        authentication::{Credentials, Mechanism},
        Error as SmtpError,
    },
    Message, SmtpTransport, Transport,
};
use serde::{Deserialize, Serialize};
use std::{env, num::ParseIntError};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum EmailError {
    #[error("SMTP error: {0}")]
    SmtpError(#[from] SmtpError),
    #[error("General SMTP error: {0}")]
    LettreError(#[from] lettre::error::Error),
    #[error("Environment variable error: {0}")]
    EnvError(#[from] std::env::VarError),
    #[error("Address parse error: {0}")]
    AddressError(#[from] lettre::address::AddressError),
    #[error("Database error: {0}")]
    DbError(#[from] tokio_postgres::Error),
    #[error("Pool error: {0}")]
    PoolError(#[from] deadpool_postgres::PoolError),
    #[error("Parse error: {0}")]
    ParseError(String),
    #[error("Other error: {0}")]
    Other(String),
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EmailNotification {
    pub to_email: String,
    pub subject: String,
    pub text_body: String,
    pub html_body: String,
}

pub struct EmailService {
    mailer: SmtpTransport,
    from_address: String,
    frontend_url: String,
}

impl EmailService {
    pub fn new() -> Result<Self, EmailError> {
        let smtp_credentials =
            Credentials::new(env::var("SMTP_USERNAME")?, env::var("SMTP_PASSWORD")?);
        let smtp_port: u16 = env::var("SMTP_PORT")?
            .parse()
            .map_err(|e: ParseIntError| EmailError::ParseError(e.to_string()))?;

        let smtp_host = env::var("SMTP_HOST")?;

        let tls_params = lettre::transport::smtp::client::TlsParameters::builder(smtp_host.clone())
            .dangerous_accept_invalid_certs(true)
            .build()
            .map_err(|e| EmailError::Other(e.to_string()))?;

        let mailer = SmtpTransport::relay(&smtp_host)
            .map_err(EmailError::SmtpError)?
            .port(smtp_port)
            .credentials(smtp_credentials)
            .authentication(vec![Mechanism::Plain])
            .tls(lettre::transport::smtp::client::Tls::Required(tls_params))
            .build();

        let from_address = env::var("SMTP_FROM_ADDRESS")?;

        Ok(EmailService {
            mailer,
            from_address,
            frontend_url: env::var("FRONTEND_URL")?,
        })
    }

    pub fn build_email_content(
        &self,
        content: &[&str],
        action_link: Option<(&str, &str)>,
    ) -> (String, String) {
        let mut text_body = String::new();
        let mut html_body = String::new();

        // Common text body construction
        text_body.push_str(&content.join("\n"));

        // Common HTML template - using table layout for email client compatibility
        html_body.push_str(&format!(
            r#"<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <!--[if mso]>
    <style type="text/css">
        table {{border-collapse:collapse;border-spacing:0;margin:0;}}
        div, td {{padding:0;}}
        div {{margin:0;}}
    </style>
    <![endif]-->
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;">
    <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="background-color: #f3f4f6;">
        <tr>
            <td align="center" style="padding: 40px 20px;">
                <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="600" style="max-width: 600px; background-color: #ffffff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
                    <!-- Header -->
                    <tr>
                        <td align="center" style="padding: 32px 24px 24px 24px;">
                            <img src="{}/assets/icons/favicon.png" alt="Lojban Dictionary Logo" style="height: 64px; width: 128px; display: block;">
                        </td>
                    </tr>
                    <!-- Content -->
                    <tr>
                        <td style="padding: 0 48px 32px 48px;">
                            <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
                                <tr>
                                    <td align="center" style="font-size: 16px; line-height: 1.6; color: #333333; padding-bottom: 24px;">
                                        {}"#,
            self.frontend_url,
            content.join("<br>")
        ));

        // Add action button if provided
        if let Some((action_text, action_url)) = action_link {
            html_body.push_str(&format!(
                r#"</td>
                                </tr>
                                <tr>
                                    <td align="center" style="padding-top: 24px; padding-bottom: 8px;">
                                        <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                                            <tr>
                                                <td align="center" style="background-color: #3b82f6; border-radius: 1000px;">
                                                    <a href="{}" style="display: inline-block; padding: 12px 32px; font-size: 16px; font-weight: 500; color: #ffffff; text-decoration: none; border-radius: 1000px;">{}</a>
                                                </td>
                                            </tr>
                                        </table>
                                    </td>
                                </tr>"#,
                action_url, action_text
            ));
        } else {
            html_body.push_str(
                r#"</td>
                                </tr>"#,
            );
        }

        // Common footer
        html_body.push_str(&format!(
            r#"                            </table>
                        </td>
                    </tr>
                    <!-- Footer -->
                    <tr>
                        <td align="center" style="padding: 32px 48px; border-top: 1px solid #e5e7eb;">
                            <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
                                <tr>
                                    <td align="center" style="font-size: 14px; line-height: 1.5; color: #6b7280;">
                                        <p style="margin: 0 0 8px 0;">This message was sent by the Lojban Dictionary service.</p>
                                        <p style="margin: 0;">© {} Lojban Dictionary</p>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>"#,
            chrono::Local::now().year()
        ));

        (text_body, html_body)
    }

    pub fn send_notification(&self, notification: EmailNotification) -> Result<(), EmailError> {
        let email = Message::builder()
            .from(self.from_address.parse()?)
            .to(notification.to_email.parse()?)
            .subject(notification.subject)
            .multipart(MultiPart::alternative_plain_html(
                notification.text_body,
                notification.html_body,
            ))
            .map_err(|e| EmailError::Other(e.to_string()))?;

        self.mailer.send(&email).map_err(EmailError::SmtpError)?;
        Ok(())
    }
}

pub async fn send_notification_emails(pool: &deadpool_postgres::Pool) -> Result<(), EmailError> {
    let client = pool.get().await?;

    let notifications = client
        .query(
            "SELECT n.*, u.email, v.word as valsi_word
             FROM user_notifications n
             JOIN users u ON n.user_id = u.userid 
             LEFT JOIN valsi v ON n.valsi_id = v.valsiid
             WHERE n.email_sent IS NULL 
             AND u.email IS NOT NULL
             AND u.email <> ''
             LIMIT 50",
            &[],
        )
        .await?;

    if notifications.is_empty() {
        return Ok(());
    }

    let email_service = EmailService::new()?;

    for row in notifications {
        let notification_id: i32 = row.get("notification_id");
        let email: String = row.get("email");
        let message: String = row.get("message");
        let notification_type: String = row.get("notification_type");
        let valsi_word: Option<String> = row.get("valsi_word");
        let link: Option<String> = row.get("link");

        let subject = match valsi_word {
            Some(word) => format!("Lojban Dictionary: {} - {}", notification_type, word),
            None => format!("Lojban Dictionary: {}", notification_type),
        };

        let message_lines: Vec<&str> = message.split('\n').collect();
        let (text_body, html_body) = email_service.build_email_content(
            &message_lines,
            link.as_ref().map(|url| ("View Update", url.as_str())),
        );

        if let Err(e) = email_service.send_notification(EmailNotification {
            to_email: email,
            subject,
            text_body,
            html_body,
        }) {
            log::error!("Failed to send notification {}: {}", notification_id, e);
            continue;
        }

        if let Err(e) = client
            .execute(
                "UPDATE user_notifications 
                 SET email_sent = CURRENT_TIMESTAMP 
                 WHERE notification_id = $1",
                &[&notification_id],
            )
            .await
        {
            log::error!(
                "Failed to mark notification {} as sent: {}",
                notification_id,
                e
            );
        }
    }

    // Clean up any remaining notifications with empty emails
    client
        .execute(
            "DELETE FROM user_notifications 
         WHERE notification_id IN (
             SELECT notification_id 
             FROM user_notifications n
             JOIN users u ON n.user_id = u.userid
             WHERE u.email IS NULL OR u.email = ''
         )",
            &[],
        )
        .await?;

    Ok(())
}

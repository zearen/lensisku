use tokio::time::{interval, Duration};

use super::service::send_notification_emails;

pub async fn run_email_notifications(pool: deadpool_postgres::Pool) {
    let mut interval = interval(Duration::from_secs(60));

    loop {
        interval.tick().await;
        match send_notification_emails(&pool).await {
            Ok(_) => {
                log::debug!("Processed notification emails successfully");
            }
            Err(e) => {
                log::error!("Error processing notification emails: {}", e);
            }
        }
    }
}

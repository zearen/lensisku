use chrono::{DateTime, Utc};
use uuid::Uuid;

#[derive(Debug)]
pub struct UserSession {
    pub id: i64,
    pub session_uuid: Uuid,
    pub user_id: i32,
    pub ip_address: String,
    pub user_agent: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub last_active_at: DateTime<Utc>,
}

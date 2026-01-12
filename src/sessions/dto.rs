use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

#[derive(Deserialize, ToSchema, IntoParams)]
pub struct PaginationParams {
    #[serde(default = "default_page")]
    #[schema(default = 1)]
    pub page: u64,
    #[serde(default = "default_limit")]
    #[schema(default = 10)]
    pub limit: u64,
}

fn default_page() -> u64 {
    1
}

fn default_limit() -> u64 {
    10
}

impl Default for PaginationParams {
    fn default() -> Self {
        Self {
            page: default_page(),
            limit: default_limit(),
        }
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct UserSessionDto {
    pub id: i64,
    pub session_uuid: Uuid,
    pub user_id: i32,
    pub ip_address: String,
    pub user_agent: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub last_active_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PaginatedUserSessionsResponse {
    pub sessions: Vec<UserSessionDto>,
    pub total_items: i64,
    pub total_pages: u64,
    pub current_page: u64,
    pub per_page: u64,
}

impl From<&super::models::UserSession> for UserSessionDto {
    fn from(session_model: &super::models::UserSession) -> Self {
        UserSessionDto {
            id: session_model.id,
            session_uuid: session_model.session_uuid,
            user_id: session_model.user_id,
            ip_address: session_model.ip_address.clone(),
            user_agent: session_model.user_agent.clone(),
            started_at: session_model.started_at,
            ended_at: session_model.ended_at,
            last_active_at: session_model.last_active_at,
        }
    }
}

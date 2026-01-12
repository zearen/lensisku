use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Deserialize, ToSchema)]
pub struct MuplisSearchQuery {
    pub query: String,
    pub page: Option<i64>,
    pub per_page: Option<i64>,
    pub sort: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct MuplisSearchResponse {
    pub entries: Vec<MuplisEntry>,
    pub total: i64,
    pub page: i64,
    pub per_page: i64,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct MuplisEntry {
    pub id: i32,
    pub lojban: String,
    pub english: String,
    pub rank: i32,
}

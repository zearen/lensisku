use actix_web::{get, web, HttpResponse, Responder};
use deadpool_postgres::Pool;

use super::dto::{MuplisSearchQuery, MuplisSearchResponse};
use super::service;

#[utoipa::path(
    get,
    tag = "muplis",
    path = "/muplis/search",
    params(
        ("query" = String, Query, description = "Search query"),
        ("page" = Option<i64>, Query, description = "Page number"),
        ("per_page" = Option<i64>, Query, description = "Items per page")
    ),
    responses(
        (status = 200, description = "Search results", body = MuplisSearchResponse),
        (status = 500, description = "Internal server error")
    ),
    summary = "Search Muplis entries",
    description = "Searches the Muplis database for entries matching the given query term. Results are \
                  paginated and include both exact and fuzzy matches. The search covers entry titles, \
                  descriptions, and content, with exact matches ranked higher than partial matches."
)]
#[get("/search")]
pub async fn search_muplis(
    pool: web::Data<Pool>,
    query: web::Query<MuplisSearchQuery>,
) -> impl Responder {
    match service::search_muplis(&pool, query.into_inner()).await {
        Ok(response) => HttpResponse::Ok().json(response),
        Err(e) => HttpResponse::InternalServerError().body(format!("Database error: {}", e)),
    }
}

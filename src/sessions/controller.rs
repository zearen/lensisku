use actix_web::{web, HttpResponse, Responder};
use actix_web_grants::protect;
use deadpool_postgres::Pool;

use crate::auth::models::Claims;
use crate::error::AppResult;
use crate::sessions::dto::{PaginatedUserSessionsResponse, PaginationParams};

/// Get current authenticated user's sessions with pagination.
#[utoipa::path(
    get,
    path = "/api/sessions/my",
    tag = "Sessions",
    params(PaginationParams),
    responses(
        (status = 200, description = "Successfully retrieved user sessions", body = PaginatedUserSessionsResponse),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal Server Error")
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn get_my_sessions(
    pool: web::Data<Pool>,
    claims: Claims,
    query: web::Query<PaginationParams>,
) -> AppResult<impl Responder> {
    let pagination = query.into_inner();

    let sessions_response = super::service::get_user_sessions(
        pool.get_ref(),
        claims.sub,
        pagination.page,
        pagination.limit,
    )
    .await?;
    Ok(HttpResponse::Ok().json(sessions_response))
}

/// Get sessions for a specific user by user_id (Admin only).
#[utoipa::path(
    get,
    path = "/api/users/{user_id}/sessions",
    tag = "Sessions",
    params(
        ("user_id" = i32, Path, description = "User ID (integer) to fetch sessions for"),
        PaginationParams
    ),
    responses(
        (status = 200, description = "Successfully retrieved user sessions", body = PaginatedUserSessionsResponse),
        (status = 401, description = "Unauthorized"),
        (status = 403, description = "Forbidden - Admin role required"),
        (status = 404, description = "User not found"),
        (status = 500, description = "Internal Server Error")
    ),
    security(
        ("bearer_auth" = ["view_user_sessions_admin"])
    )
)]
#[protect(any("view_user_sessions_admin"))]
pub async fn get_user_sessions_admin(
    pool: web::Data<Pool>,
    _claims: Claims,
    path: web::Path<i32>,
    query: web::Query<PaginationParams>,
) -> AppResult<impl Responder> {
    let user_id_to_fetch = path.into_inner();
    let pagination = query.into_inner();

    let sessions_response = super::service::get_user_sessions(
        pool.get_ref(),
        user_id_to_fetch,
        pagination.page,
        pagination.limit,
    )
    .await?;
    Ok(HttpResponse::Ok().json(sessions_response))
}

pub fn init_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api")
            .service(web::resource("/sessions/my").route(web::get().to(get_my_sessions)))
            .service(
                web::resource("/users/{user_id}/sessions")
                    .route(web::get().to(get_user_sessions_admin)),
            ),
    );
}

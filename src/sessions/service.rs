use crate::error::{AppError, AppResult};
use crate::sessions::dto::{PaginatedUserSessionsResponse, UserSessionDto};
use crate::sessions::models::UserSession;
use chrono::{DateTime, Utc};
use deadpool_postgres::Pool;
use std::net::IpAddr;
use uuid::Uuid;

/// Starts a new user session.
pub async fn start_session(
    pool: &Pool,
    user_id: i32,
    ip_address: String,
    user_agent: String,
) -> AppResult<UserSession> {
    let parsed_ip_address: Option<IpAddr> = ip_address.parse().ok();
    let client = pool
        .get()
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;
    let row = client
        .query_one(
            r#"
        INSERT INTO user_sessions (user_id, ip_address, user_agent, session_uuid) -- Added session_uuid
        VALUES ($1, $2, $3, gen_random_uuid()) -- Generate UUID on insert
        RETURNING id, session_uuid, user_id, ip_address, user_agent, started_at, ended_at, last_active_at
        "#,
            &[&user_id, &parsed_ip_address, &user_agent],
        )
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;

    let db_ip_address: Option<IpAddr> = row
        .try_get("ip_address")
        .map_err(|e| AppError::Database(format!("Failed to get ip_address: {}", e)))?;
    let session = UserSession {
        id: row
            .try_get("id")
            .map_err(|e| AppError::Database(format!("Failed to get id: {}", e)))?,
        user_id: row
            .try_get("user_id")
            .map_err(|e| AppError::Database(format!("Failed to get user_id: {}", e)))?,
        ip_address: db_ip_address
            .map(|ip| ip.to_string())
            .unwrap_or_else(|| "unknown".to_string()),
        user_agent: row
            .try_get("user_agent")
            .map_err(|e| AppError::Database(format!("Failed to get user_agent: {}", e)))?,
        started_at: row
            .try_get("started_at")
            .map_err(|e| AppError::Database(format!("Failed to get started_at: {}", e)))?,
        session_uuid: row
            .try_get("session_uuid")
            .map_err(|e| AppError::Database(format!("Failed to get session_uuid: {}", e)))?,
        ended_at: row
            .try_get::<_, Option<DateTime<Utc>>>("ended_at")
            .map_err(|e| AppError::Database(format!("Failed to get ended_at: {}", e)))?,
        last_active_at: row
            .try_get("last_active_at")
            .map_err(|e| AppError::Database(format!("Failed to get last_active_at: {}", e)))?,
    };
    Ok(session)
}

/// Ends an active user session.
pub async fn end_session(pool: &Pool, user_id: i32) -> AppResult<Option<UserSession>> {
    let client = pool
        .get()
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;
    let ended_at_time = Utc::now();
    let row_opt = client
        .query_opt(
        r#"WITH latest_session AS (
            SELECT id
            FROM user_sessions
            WHERE user_id = $1 AND ended_at IS NULL
            ORDER BY last_active_at DESC
            LIMIT 1
        )
        UPDATE user_sessions us
        SET ended_at = $2, last_active_at = $2
        FROM latest_session
        WHERE us.id = latest_session.id
        RETURNING us.id, us.session_uuid, us.user_id, us.ip_address, us.user_agent, us.started_at, us.ended_at, us.last_active_at
        "#,
            &[&user_id, &ended_at_time],
        )
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;

    if let Some(row) = row_opt {
        let db_ip_address: Option<IpAddr> = row
            .try_get("ip_address")
            .map_err(|e| AppError::Database(format!("Failed to get ip_address: {}", e)))?;
        Ok(Some(UserSession {
            id: row
                .try_get("id")
                .map_err(|e| AppError::Database(format!("Failed to get id: {}", e)))?,
            session_uuid: row
                .try_get("session_uuid")
                .map_err(|e| AppError::Database(format!("Failed to get session_uuid: {}", e)))?,
            user_id: row
                .try_get("user_id")
                .map_err(|e| AppError::Database(format!("Failed to get user_id: {}", e)))?,
            ip_address: db_ip_address
                .map(|ip| ip.to_string())
                .unwrap_or_else(|| "unknown".to_string()),
            user_agent: row
                .try_get("user_agent")
                .map_err(|e| AppError::Database(format!("Failed to get user_agent: {}", e)))?,
            started_at: row
                .try_get("started_at")
                .map_err(|e| AppError::Database(format!("Failed to get started_at: {}", e)))?,
            ended_at: Some(
                row.try_get("ended_at")
                    .map_err(|e| AppError::Database(format!("Failed to get ended_at: {}", e)))?,
            ),
            last_active_at: row
                .try_get("last_active_at")
                .map_err(|e| AppError::Database(format!("Failed to get last_active_at: {}", e)))?,
        }))
    } else {
        Ok(None)
    }
}

/// Updates the last active time, IP address, and user agent for an active session.
pub async fn update_session_activity(
    pool: &Pool,
    user_id: i32,
    session_id: i64,
    ip_address: String,
    user_agent: String,
) -> AppResult<Option<UserSession>> {
    let parsed_ip_address: Option<IpAddr> = ip_address.parse().ok();
    let client = pool
        .get()
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;
    let last_active_time = Utc::now();
    let row_opt = client
        .query_opt(
            r#"
        UPDATE user_sessions
        SET last_active_at = $1, ip_address = $2, user_agent = $3
        WHERE user_id = $4 AND id = $5 AND ended_at IS NULL
        RETURNING id, session_uuid, user_id, ip_address, user_agent, started_at, ended_at, last_active_at
        "#,
            &[&last_active_time, &parsed_ip_address, &user_agent, &user_id, &session_id],
        )
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;

    if let Some(row) = row_opt {
        let db_ip_address: Option<IpAddr> = row
            .try_get("ip_address")
            .map_err(|e| AppError::Database(format!("Failed to get ip_address: {}", e)))?;
        Ok(Some(UserSession {
            id: row
                .try_get("id")
                .map_err(|e| AppError::Database(format!("Failed to get id: {}", e)))?,
            session_uuid: row
                .try_get("session_uuid")
                .map_err(|e| AppError::Database(format!("Failed to get session_uuid: {}", e)))?,
            user_id: row
                .try_get("user_id")
                .map_err(|e| AppError::Database(format!("Failed to get user_id: {}", e)))?,
            ip_address: db_ip_address
                .map(|ip| ip.to_string())
                .unwrap_or_else(|| "unknown".to_string()),
            user_agent: row
                .try_get("user_agent")
                .map_err(|e| AppError::Database(format!("Failed to get user_agent: {}", e)))?,
            started_at: row
                .try_get("started_at")
                .map_err(|e| AppError::Database(format!("Failed to get started_at: {}", e)))?,
            ended_at: row
                .try_get::<_, Option<DateTime<Utc>>>("ended_at")
                .map_err(|e| AppError::Database(format!("Failed to get ended_at: {}", e)))?,
            last_active_at: row
                .try_get("last_active_at")
                .map_err(|e| AppError::Database(format!("Failed to get last_active_at: {}", e)))?,
        }))
    } else {
        Ok(None)
    }
}

/// Fetches user sessions with pagination.
pub async fn get_user_sessions(
    pool: &Pool,
    user_id: i32,
    page: u64,
    limit: u64,
) -> AppResult<PaginatedUserSessionsResponse> {
    let client = pool
        .get()
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;

    // Calculate offset
    let offset = (page.saturating_sub(1)) * limit;

    // Get total count of sessions for the user
    let count_row = client
        .query_one(
            "SELECT COUNT(*) FROM user_sessions WHERE user_id = $1",
            &[&user_id],
        )
        .await
        .map_err(|e| AppError::Database(format!("Failed to count user sessions: {}", e)))?;
    let total_items: i64 = count_row.get(0);

    // Fetch paginated sessions
    let rows = client
        .query(
            r#"
        SELECT id, session_uuid, user_id, ip_address, user_agent, started_at, ended_at, last_active_at
        FROM user_sessions
        WHERE user_id = $1
        ORDER BY started_at DESC
        LIMIT $2 OFFSET $3
        "#,
            &[&user_id, &(limit as i64), &(offset as i64)],
        )
        .await
        .map_err(|e| AppError::Database(format!("Failed to fetch user sessions: {}", e)))?;

    let sessions: Vec<UserSessionDto> = rows
        .into_iter()
        .map(|row| -> AppResult<UserSession> {
            let db_ip_address: Option<IpAddr> = row.try_get("ip_address").map_err(|e| {
                AppError::Database(format!("Failed to get ip_address from row: {}", e))
            })?;
            Ok(UserSession {
                id: row
                    .try_get("id")
                    .map_err(|e| AppError::Database(format!("Failed to get id from row: {}", e)))?,
                session_uuid: row.try_get("session_uuid").map_err(|e| {
                    AppError::Database(format!("Failed to get session_uuid from row: {}", e))
                })?,
                user_id: row.try_get("user_id").map_err(|e| {
                    AppError::Database(format!("Failed to get user_id from row: {}", e))
                })?,
                ip_address: db_ip_address
                    .map(|ip| ip.to_string())
                    .unwrap_or_else(|| "unknown".to_string()),
                user_agent: row.try_get("user_agent").map_err(|e| {
                    AppError::Database(format!("Failed to get user_agent from row: {}", e))
                })?,
                started_at: row.try_get("started_at").map_err(|e| {
                    AppError::Database(format!("Failed to get started_at from row: {}", e))
                })?,
                ended_at: row
                    .try_get::<_, Option<DateTime<Utc>>>("ended_at")
                    .map_err(|e| {
                        AppError::Database(format!("Failed to get ended_at from row: {}", e))
                    })?,
                last_active_at: row.try_get("last_active_at").map_err(|e| {
                    AppError::Database(format!("Failed to get last_active_at from row: {}", e))
                })?,
            })
        })
        .collect::<AppResult<Vec<UserSession>>>()?
        .iter()
        .map(UserSessionDto::from)
        .collect();

    let total_pages = if total_items == 0 {
        0
    } else {
        (total_items as f64 / limit as f64).ceil() as u64
    };

    Ok(PaginatedUserSessionsResponse {
        sessions,
        total_items,
        total_pages,
        current_page: page,
        per_page: limit,
    })
}

pub async fn get_session_id_from_uuid(pool: &Pool, session_uuid: Uuid) -> AppResult<Option<i64>> {
    let client = pool
        .get()
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;
    let row_opt = client
        .query_opt(
            "SELECT id FROM user_sessions WHERE session_uuid = $1 AND ended_at IS NULL",
            &[&session_uuid],
        )
        .await
        .map_err(|e| AppError::Database(format!("Failed to fetch session ID by UUID: {}", e)))?;

    if let Some(row) = row_opt {
        Ok(Some(row.try_get("id").map_err(|e| {
            AppError::Database(format!("Failed to get id from row: {}", e))
        })?))
    } else {
        Ok(None)
    }
}

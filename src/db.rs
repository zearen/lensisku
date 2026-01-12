use crate::{AppError, AppResult};
use deadpool_postgres::Pool;
use log::{error, info};

mod embedded {
    use refinery::embed_migrations;
    embed_migrations!("./migrations");
}

pub async fn enable_extensions(pool: &Pool) -> AppResult<()> {
    // Use ? for automatic error conversion via From trait
    let client = pool
        .get()
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;
    client
        .execute("CREATE EXTENSION IF NOT EXISTS pg_trgm", &[])
        .await
        .map_err(|e| AppError::Database(e.to_string()))?; // Map error explicitly if From not implemented for specific error subtype
    client
        .execute("CREATE EXTENSION IF NOT EXISTS vector", &[])
        .await
        .map_err(|e| AppError::Database(e.to_string()))?; // Map error explicitly
    Ok(())
}

pub async fn run_migrations(pool: &Pool) -> AppResult<()> {
    // Use ? for automatic error conversion via From trait
    let mut conn = pool
        .get()
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;
    embedded::migrations::runner()
        .run_async(&mut **conn)
        .await
        .map_err(|e| {
            // Keep map_err for logging specific context before converting
            error!("Error running migrations: {:?}", e);
            AppError::Migration(e.to_string())
        })?;
    info!("Migrations ran successfully");
    Ok(())
}

pub async fn get_message_count(pool: &Pool) -> AppResult<i64> {
    // Use ? for automatic error conversion via From trait
    let conn = pool
        .get()
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;
    let row = conn
        .query_one("SELECT COUNT(*) FROM messages", &[])
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;
    // row.get returns Result, use ? to propagate error and convert
    row.try_get(0)
        .map_err(|e| AppError::Database(e.to_string()))
}

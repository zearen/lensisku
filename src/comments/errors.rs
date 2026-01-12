#[derive(Debug, thiserror::Error)]
pub enum ReactionError {
    #[error("Reaction string too long")]
    TooLong,
    #[error("Maximum of 5 reactions per comment reached")]
    LimitReached,
    #[error("Database error: {0}")]
    Database(#[from] tokio_postgres::Error),
    #[error("Pool error: {0}")]
    Pool(#[from] deadpool_postgres::PoolError),
}

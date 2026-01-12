use crate::{AppError, AppResult};
use deadpool_postgres::Transaction;

pub async fn verify_collection_ownership(
    transaction: &Transaction<'_>,
    collection_id: i32,
    user_id: i32,
) -> AppResult<()> {
    let owner_id: i32 = transaction
        .query_one(
            "SELECT user_id FROM collections WHERE collection_id = $1",
            &[&collection_id],
        )
        .await?
        .get("user_id");

    if owner_id != user_id {
        return Err(AppError::Auth(
            "Access Denied: Collection does not belong to user".to_string(),
        ));
    }
    Ok(())
}

pub async fn verify_flashcard_ownership(
    transaction: &Transaction<'_>,
    flashcard_id: i32,
    user_id: i32,
) -> AppResult<()> {
    let owner_id: i32 = transaction
        .query_one(
            "SELECT c.user_id
             FROM flashcards f
             JOIN collections c ON f.collection_id = c.collection_id
             WHERE f.id = $1",
            &[&flashcard_id],
        )
        .await?
        .get("user_id");

    if owner_id != user_id {
        return Err(AppError::Auth(
            "Access Denied: Flashcard does not belong to user".to_string(),
        ));
    }
    Ok(())
}

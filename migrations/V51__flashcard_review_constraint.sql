-- First clean up any duplicates, keeping the most recent record
WITH ranked_progress AS (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY user_id, flashcard_id, card_side 
               ORDER BY last_reviewed_at DESC NULLS LAST, id DESC
           ) as rn
    FROM user_flashcard_progress
    WHERE NOT archived
)
DELETE FROM user_flashcard_progress
WHERE id IN (
    SELECT id FROM ranked_progress WHERE rn > 1
);

-- Add unique constraint
DROP INDEX IF EXISTS idx_unique_active_progress;

CREATE UNIQUE INDEX idx_unique_active_progress 
ON user_flashcard_progress (user_id, flashcard_id, card_side) 
WHERE NOT archived;
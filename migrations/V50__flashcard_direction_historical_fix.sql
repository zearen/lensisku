-- Add missing reverse side progress for flashcards with direction='both'
INSERT INTO user_flashcard_progress (user_id, flashcard_id, card_side, status, next_review_at)
SELECT 
    ufp.user_id,
    ufp.flashcard_id,
    'reverse' as card_side,
    'new' as status,
    CURRENT_TIMESTAMP as next_review_at
FROM user_flashcard_progress ufp
JOIN flashcards f ON f.id = ufp.flashcard_id
WHERE f.direction = 'both'
AND NOT EXISTS (
    SELECT 1 
    FROM user_flashcard_progress ufp2 
    WHERE ufp2.flashcard_id = ufp.flashcard_id 
    AND ufp2.user_id = ufp.user_id 
    AND ufp2.card_side = 'reverse'
);

ALTER TABLE user_flashcard_progress 
ADD COLUMN archived BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_flashcard_progress_archived ON user_flashcard_progress(archived);
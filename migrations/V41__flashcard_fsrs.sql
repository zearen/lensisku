-- Modify existing user_flashcard_progress table
ALTER TABLE user_flashcard_progress
ADD COLUMN stability FLOAT NOT NULL DEFAULT 0.0,
ADD COLUMN difficulty FLOAT NOT NULL DEFAULT 0.0;

-- Create flashcard reviews history table
CREATE TABLE flashcard_review_history (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(userid),
    flashcard_id INTEGER NOT NULL REFERENCES flashcards(id),
    rating INTEGER NOT NULL, -- 1-4 rating
    elapsed_days INTEGER NOT NULL, -- days since last review
    scheduled_days INTEGER NOT NULL, -- days scheduled for next review
    state JSONB NOT NULL, -- stores stability and difficulty
    review_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id, flashcard_id) 
        REFERENCES user_flashcard_progress(user_id, flashcard_id)
        ON DELETE CASCADE
);

CREATE INDEX idx_flashcard_review_history_lookup 
ON flashcard_review_history(user_id, flashcard_id, review_time);
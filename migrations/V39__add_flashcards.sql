-- Flashcards table
CREATE TABLE flashcards (
    id SERIAL PRIMARY KEY,
    collection_id INTEGER NOT NULL REFERENCES collections(collection_id) ON DELETE CASCADE,
    definition_id INTEGER NOT NULL REFERENCES definitions(definitionid) ON DELETE CASCADE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(collection_id, definition_id)
);

-- User progress table
CREATE TYPE flashcard_status AS ENUM ('new', 'learning', 'review', 'graduated');

CREATE TABLE user_flashcard_progress (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(userid) ON DELETE CASCADE,
    flashcard_id INTEGER NOT NULL REFERENCES flashcards(id) ON DELETE CASCADE,
    ease_factor FLOAT NOT NULL DEFAULT 2.5,
    interval INTEGER NOT NULL DEFAULT 0,  -- in minutes
    review_count INTEGER NOT NULL DEFAULT 0,
    last_reviewed_at TIMESTAMP WITH TIME ZONE,
    next_review_at TIMESTAMP WITH TIME ZONE,
    status flashcard_status NOT NULL DEFAULT 'new',
    UNIQUE(user_id, flashcard_id)
);

-- Indexes for better performance
CREATE INDEX idx_flashcards_collection ON flashcards(collection_id);
CREATE INDEX idx_user_progress_user ON user_flashcard_progress(user_id);
CREATE INDEX idx_user_progress_next_review ON user_flashcard_progress(next_review_at);
CREATE INDEX idx_user_progress_status ON user_flashcard_progress(status);
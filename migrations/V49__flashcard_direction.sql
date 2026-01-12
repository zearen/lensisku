-- Create direction enum type
CREATE TYPE flashcard_direction AS ENUM ('direct', 'reverse', 'both');

-- Add direction column to flashcards table
ALTER TABLE flashcards
ADD COLUMN direction flashcard_direction NOT NULL DEFAULT 'direct';

-- First add the card_side column
ALTER TABLE user_flashcard_progress
ADD COLUMN card_side TEXT NOT NULL DEFAULT 'direct';

-- Drop existing foreign keys and constraints
ALTER TABLE flashcard_review_history
DROP CONSTRAINT IF EXISTS flashcard_review_history_user_id_flashcard_id_fkey;

ALTER TABLE user_flashcard_progress
DROP CONSTRAINT IF EXISTS user_flashcard_progress_user_id_flashcard_id_key;

-- Add new composite unique constraint
ALTER TABLE user_flashcard_progress
ADD CONSTRAINT user_flashcard_progress_unique_side 
UNIQUE (user_id, flashcard_id, card_side);

-- Add card_side column to flashcard_review_history
ALTER TABLE flashcard_review_history
ADD COLUMN card_side TEXT NOT NULL DEFAULT 'direct';

-- Now recreate the foreign key with matching columns
ALTER TABLE flashcard_review_history
ADD CONSTRAINT flashcard_review_history_user_progress_fkey
FOREIGN KEY (user_id, flashcard_id, card_side)
REFERENCES user_flashcard_progress(user_id, flashcard_id, card_side);

-- Add index for efficient lookups
CREATE INDEX idx_flashcard_progress_side 
ON user_flashcard_progress(flashcard_id, user_id, card_side);

-- Update views
DROP VIEW if exists flashcard_details;

CREATE VIEW flashcard_details AS
SELECT 
    f.*,
    v.word,
    d.definition,
    ci.notes
FROM flashcards f
JOIN definitions d ON f.definition_id = d.definitionid
JOIN valsi v ON d.valsiid = v.valsiid
JOIN collection_items ci ON f.item_id = ci.item_id;
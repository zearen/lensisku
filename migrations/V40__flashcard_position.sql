-- Add position column with default ordering by creation date
ALTER TABLE flashcards
ADD COLUMN position INTEGER NOT NULL DEFAULT 0;

-- Update existing flashcards with positions based on creation order within each collection
WITH ordered_flashcards AS (
    SELECT 
        id,
        collection_id,
        ROW_NUMBER() OVER (PARTITION BY collection_id ORDER BY created_at ASC) - 1 as new_position
    FROM flashcards
)
UPDATE flashcards f
SET position = of.new_position
FROM ordered_flashcards of
WHERE f.id = of.id;

-- Create index for efficient ordering queries
CREATE INDEX idx_flashcards_position ON flashcards(collection_id, position);

-- Add constraint to ensure positions are unique within a collection
ALTER TABLE flashcards
ADD CONSTRAINT unique_position_per_collection UNIQUE (collection_id, position);
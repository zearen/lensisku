-- Create temporary table to preserve notes
CREATE TABLE flashcard_temp_notes (
    id INTEGER PRIMARY KEY,
    notes TEXT
);

-- Save existing notes
INSERT INTO flashcard_temp_notes (id, notes)
SELECT id, notes FROM flashcards
WHERE notes IS NOT NULL;

-- Add item_id column to flashcards
ALTER TABLE flashcards 
ADD COLUMN item_id INTEGER REFERENCES collection_items(item_id);

-- Update item_id based on matching collection_items
UPDATE flashcards f
SET item_id = ci.item_id
FROM collection_items ci
WHERE f.collection_id = ci.collection_id 
AND f.definition_id = ci.definition_id;

-- For flashcards without matching collection_items, create new items
INSERT INTO collection_items (collection_id, definition_id, notes, position)
SELECT f.collection_id, f.definition_id, tn.notes, 
    COALESCE((
        SELECT MAX(position) + 1 
        FROM collection_items 
        WHERE collection_id = f.collection_id
    ), 0)
FROM flashcards f
LEFT JOIN flashcard_temp_notes tn ON f.id = tn.id
WHERE f.item_id IS NULL;

-- Update flashcards with newly created collection_items
UPDATE flashcards f
SET item_id = ci.item_id
FROM collection_items ci
WHERE f.collection_id = ci.collection_id 
AND f.definition_id = ci.definition_id
AND f.item_id IS NULL;

-- Make item_id required
ALTER TABLE flashcards 
ALTER COLUMN item_id SET NOT NULL;

-- Drop notes column
ALTER TABLE flashcards 
DROP COLUMN notes;

-- Clean up
DROP TABLE flashcard_temp_notes;

-- Add index for performance
CREATE INDEX idx_flashcards_item_id ON flashcards(item_id);

-- add view for easier access 
CREATE OR REPLACE VIEW flashcard_details AS
SELECT 
    f.*,
    v.word,
    d.definition,
    ci.notes
FROM flashcards f
JOIN definitions d ON f.definition_id = d.definitionid
JOIN valsi v ON d.valsiid = v.valsiid
JOIN collection_items ci ON f.item_id = ci.item_id;
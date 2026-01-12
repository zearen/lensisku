-- Drop dependent view first
DROP VIEW flashcard_details;

-- Remove foreign key constraint and column
ALTER TABLE flashcards
    DROP CONSTRAINT flashcards_definition_id_fkey,
    DROP COLUMN definition_id;

-- Recreate view without definition_id reference
CREATE VIEW flashcard_details AS
SELECT 
    f.*,
    ci.notes,
    ci.auto_progress,
    ci.definition_id,
    v.word,
    d.definition,
    d.langid as definition_language_id
FROM flashcards f
JOIN collection_items ci ON f.item_id = ci.item_id
LEFT JOIN definitions d ON ci.definition_id = d.definitionid
LEFT JOIN valsi v ON d.valsiid = v.valsiid;
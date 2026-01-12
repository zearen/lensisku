ALTER TABLE collection_items
ADD COLUMN auto_progress BOOLEAN NOT NULL DEFAULT true;

-- Recreate the flashcard_details view to include the new column
DROP VIEW IF EXISTS flashcard_details;

CREATE VIEW flashcard_details AS
SELECT 
    f.*,
    v.word,
    d.definition,
    d.langid as definition_language_id,
    ci.notes,
    ci.auto_progress
FROM flashcards f
JOIN collection_items ci ON f.item_id = ci.item_id
JOIN definitions d ON f.definition_id = d.definitionid
JOIN valsi v ON d.valsiid = v.valsiid;
DROP VIEW IF EXISTS flashcard_details;

CREATE VIEW flashcard_details AS
SELECT 
    f.*,
    v.word,
    d.definition,
    d.langid as definition_language_id,
    ci.notes
FROM flashcards f
JOIN definitions d ON f.definition_id = d.definitionid
JOIN valsi v ON d.valsiid = v.valsiid
JOIN collection_items ci ON f.item_id = ci.item_id;
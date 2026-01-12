-- Step 1: Clean up duplicate collection_id/item_id pairs
WITH duplicates AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY collection_id, item_id ORDER BY id) AS rnum
    FROM flashcards
)
DELETE FROM flashcards
WHERE id IN (SELECT id FROM duplicates WHERE rnum > 1);

-- Step 2: Add new collection/item unique constraint
ALTER TABLE flashcards
    ADD CONSTRAINT flashcards_collection_item_unique UNIQUE (collection_id, item_id);

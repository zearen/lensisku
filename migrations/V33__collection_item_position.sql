-- Add to your migrations folder with appropriate version number
ALTER TABLE collection_items ADD COLUMN position INT NOT NULL DEFAULT 0;

-- Update existing items with sequential positions
WITH numbered_items AS (
  SELECT item_id, collection_id, 
         ROW_NUMBER() OVER (PARTITION BY collection_id ORDER BY added_at) - 1 as new_position
  FROM collection_items
)
UPDATE collection_items ci
SET position = ni.new_position
FROM numbered_items ni
WHERE ci.item_id = ni.item_id;

-- Add index for performance
CREATE INDEX idx_collection_items_position ON collection_items(collection_id, position);
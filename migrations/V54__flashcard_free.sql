-- Add free_content columns
ALTER TABLE collection_items ADD COLUMN free_content_front TEXT;
ALTER TABLE collection_items ADD COLUMN free_content_back TEXT;

-- Mark definition_id as optional
ALTER TABLE collection_items ALTER COLUMN definition_id DROP NOT NULL;

-- Create constraint to ensure either definition_id or free content is present
ALTER TABLE collection_items 
ADD CONSTRAINT valid_content_check 
CHECK (
    (definition_id IS NOT NULL AND free_content_front IS NULL AND free_content_back IS NULL) OR
    (definition_id IS NULL AND free_content_front IS NOT NULL AND free_content_back IS NOT NULL)
);
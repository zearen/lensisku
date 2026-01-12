-- Add new columns to collection_items table
ALTER TABLE collection_items
ADD COLUMN langid INTEGER NULL REFERENCES languages(langid),
ADD COLUMN owner_user_id INTEGER NULL REFERENCES users(userid),
ADD COLUMN license VARCHAR(50) NULL,
ADD COLUMN script VARCHAR(4) NULL,
ADD COLUMN is_original BOOLEAN NOT NULL DEFAULT TRUE,
ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Add comments to the new columns
COMMENT ON COLUMN collection_items.langid IS 'Language ID of the item content, references languages table.';
COMMENT ON COLUMN collection_items.owner_user_id IS 'User ID of the sentence owner, references users table.';
COMMENT ON COLUMN collection_items.license IS 'License of the item content (e.g., CC BY 2.0 FR).';
COMMENT ON COLUMN collection_items.script IS 'ISO 15924 script code (e.g., Latn, Cyrl).';
COMMENT ON COLUMN collection_items.is_original IS 'TRUE if the sentence was not created as a direct translation of another.';
COMMENT ON COLUMN collection_items.updated_at IS 'Timestamp of the last update to the item.';

-- Create a trigger function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.trigger_set_collection_item_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add the trigger to the collection_items table
CREATE TRIGGER set_timestamp_collection_items
BEFORE UPDATE ON collection_items
FOR EACH ROW
EXECUTE FUNCTION public.trigger_set_collection_item_timestamp();

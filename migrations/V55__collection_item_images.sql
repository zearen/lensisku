CREATE TABLE collection_item_images (
    id SERIAL PRIMARY KEY,
    item_id INTEGER NOT NULL REFERENCES collection_items(item_id) ON DELETE CASCADE,
    image_data BYTEA NOT NULL,
    mime_type TEXT NOT NULL,
    side TEXT NOT NULL CHECK (side IN ('front', 'back')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(item_id, side)
);

-- Add indexes for performance
CREATE INDEX idx_collection_item_images_item ON collection_item_images(item_id);
CREATE INDEX idx_collection_item_images_cleanup ON collection_item_images(created_at);

-- Function to clean up orphaned images
CREATE OR REPLACE FUNCTION cleanup_item_images() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM collection_item_images WHERE item_id = OLD.item_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Add trigger to clean up orphaned images when item is deleted
CREATE TRIGGER cleanup_collection_item_images
    BEFORE DELETE ON collection_items
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_item_images();
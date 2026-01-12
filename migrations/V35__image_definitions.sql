CREATE TABLE definition_images (
    id SERIAL PRIMARY KEY,
    definition_id INTEGER NOT NULL REFERENCES definitions(definitionid) ON DELETE CASCADE,
    image_data BYTEA NOT NULL,
    mime_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT one_image_per_definition UNIQUE (definition_id)
);

-- Add function to clean up orphaned images
CREATE OR REPLACE FUNCTION cleanup_orphaned_images() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM definition_images WHERE definition_id = OLD.definitionid;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Add trigger to clean up orphaned images when definition is deleted
CREATE TRIGGER cleanup_definition_images
    BEFORE DELETE ON definitions
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_orphaned_images();
-- Drop unique constraint to allow multiple images
ALTER TABLE definition_images DROP CONSTRAINT one_image_per_definition;

-- Add new columns for multiple images support
ALTER TABLE definition_images 
    ADD COLUMN description TEXT,
    ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN created_by INTEGER REFERENCES users(userid),
    ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;

-- Update existing rows to set created_by
UPDATE definition_images di
SET created_by = d.userid
FROM definitions d
WHERE di.definition_id = d.definitionid
AND di.created_by IS NULL;

-- Make created_by NOT NULL after populating existing rows
ALTER TABLE definition_images 
    ALTER COLUMN created_by SET NOT NULL;

-- Add index for faster lookups if not exists
CREATE INDEX IF NOT EXISTS idx_definition_images_definition_id 
    ON definition_images(definition_id);

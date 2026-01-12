-- Add column with default for existing records
ALTER TABLE users 
ADD COLUMN created_at timestamp NOT NULL 
DEFAULT '1970-01-01 00:00:00';

-- Remove the default constraint for future records
ALTER TABLE users 
ALTER COLUMN created_at DROP DEFAULT;
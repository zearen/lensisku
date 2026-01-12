-- Change the column type to text to support longer hashes
-- We use USING to preserve existing data
ALTER TABLE users 
  ALTER COLUMN password TYPE text 
  USING password::text;

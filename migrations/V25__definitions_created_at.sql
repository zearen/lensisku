-- Add created_at column
ALTER TABLE definitions ADD COLUMN created_at TIMESTAMPTZ;

-- Convert existing time integer field to timestamptz and set created_at
UPDATE definitions 
SET created_at = to_timestamp(COALESCE(time, EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)::integer))
WHERE created_at IS NULL;

-- Make created_at not null and set default
ALTER TABLE definitions 
  ALTER COLUMN created_at SET NOT NULL,
  ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_definitions_created_at ON definitions(created_at);
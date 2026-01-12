-- Add metadata column to definitions
ALTER TABLE definitions 
ADD COLUMN metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Revert embedding column back to all-MiniLM-L6-v2 (384 dimensions)
-- This will clear all existing embeddings as they are incompatible

DROP INDEX IF EXISTS idx_definitions_embedding_vector;

ALTER TABLE definitions 
ALTER COLUMN embedding TYPE vector(384) USING NULL;

-- Recreate index for 384 dimensions
CREATE INDEX IF NOT EXISTS idx_definitions_embedding_vector ON definitions 
USING ivfflat (embedding vector_cosine_ops) 
WITH (lists = 100)
WHERE embedding IS NOT NULL;

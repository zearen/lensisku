-- Update embedding column to support BAAI/bge-m3 (1024 dimensions)
-- This will clear all existing embeddings as they are incompatible

DROP INDEX IF EXISTS idx_definitions_embedding_vector;

ALTER TABLE definitions 
ALTER COLUMN embedding TYPE vector(1024) USING NULL;

-- Recreate index for 1024 dimensions
CREATE INDEX IF NOT EXISTS idx_definitions_embedding_vector ON definitions 
USING ivfflat (embedding vector_cosine_ops) 
WITH (lists = 100)
WHERE embedding IS NOT NULL;


-- Add GIN indexes with pg_trgm for text search performance
-- These indexes enable fast ILIKE and similarity searches

-- Index for valsi word search
CREATE INDEX IF NOT EXISTS idx_valsi_word_gin ON valsi USING gin (word gin_trgm_ops);

-- Index for valsi rafsi search (if frequently searched)
CREATE INDEX IF NOT EXISTS idx_valsi_rafsi_gin ON valsi USING gin (rafsi gin_trgm_ops) WHERE rafsi IS NOT NULL;

-- Indexes for definition text search
CREATE INDEX IF NOT EXISTS idx_definitions_definition_gin ON definitions USING gin (definition gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_definitions_notes_gin ON definitions USING gin (notes gin_trgm_ops) WHERE notes IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_definitions_selmaho_gin ON definitions USING gin (selmaho gin_trgm_ops) WHERE selmaho IS NOT NULL;

-- Composite indexes for common filter combinations
CREATE INDEX IF NOT EXISTS idx_valsi_source_langid_word ON valsi (source_langid, word);
CREATE INDEX IF NOT EXISTS idx_definitions_langid_valsiid ON definitions (langid, valsiid);

-- pgvector index for semantic search
-- Using IVFFlat index (compatible with older PostgreSQL versions)
-- For PostgreSQL 17+, consider HNSW index instead for better quality
CREATE INDEX IF NOT EXISTS idx_definitions_embedding_vector ON definitions 
USING ivfflat (embedding vector_cosine_ops) 
WITH (lists = 100)
WHERE embedding IS NOT NULL;

-- Note: The lists parameter should be tuned based on your data size
-- General rule: lists = rows / 1000 for datasets with < 1M rows
-- For larger datasets, use lists = sqrt(rows)


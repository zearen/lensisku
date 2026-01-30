-- Invalidate all non-Lojban definition embeddings so the background job recalculates
-- them with improved preprocessing (space instead of [UNK], structural prefix stripping,
-- type-based note exclusion, fu'ivla notes cap). See docs/embedding_analysis_findings.md.
UPDATE definitions
SET embedding = NULL
WHERE langid != 1 AND definition != '' AND embedding IS NOT NULL;

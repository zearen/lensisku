-- Remove the unique constraint on the space-removed version of the valsi word
ALTER TABLE valsi DROP CONSTRAINT IF EXISTS valsi_unique_word_nospaces;

-- Drop the old unique constraint on just the word
ALTER TABLE public.valsi DROP CONSTRAINT valsi_word_key;

-- Add a new unique constraint on word and source_langid
ALTER TABLE public.valsi ADD CONSTRAINT valsi_word_source_langid_key UNIQUE (word, source_langid);

-- Migrationscripts for refinery

--
-- Create migration V86__mgraton
--
-- We derive the migration name from the file name and trim leading and trailing underscores and whitespace.


ALTER TABLE public.comments
ALTER COLUMN parentid DROP NOT NULL;

UPDATE public.comments
SET parentid = NULL
WHERE parentid = 0;
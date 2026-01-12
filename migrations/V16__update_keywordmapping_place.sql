BEGIN;

-- Alter the 'place' column type from int2 to int4
ALTER TABLE keywordmapping
ALTER COLUMN place TYPE int4;

COMMIT;

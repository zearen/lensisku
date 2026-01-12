-- Add etymology column to definitions
ALTER TABLE definitions ADD COLUMN etymology TEXT;

-- Create index for better performance
CREATE INDEX idx_definitions_etymology ON definitions(etymology) WHERE etymology IS NOT NULL;

-- First, handle valsi that have English definitions
WITH ranked_english_definitions AS (
    SELECT 
        d.definitionid,
        d.valsiid,
        d.time,
        e.content AS etymology_content,
        ROW_NUMBER() OVER (PARTITION BY d.valsiid ORDER BY d.time ASC) AS rn
    FROM definitions d
    JOIN etymology e ON d.valsiid = e.valsiid
    WHERE d.langid = (SELECT langid FROM languages WHERE tag = 'en')
)
UPDATE definitions d
SET etymology = r.etymology_content
FROM ranked_english_definitions r
WHERE d.definitionid = r.definitionid
AND r.rn = 1;

-- Then, handle valsi that have no English definitions but have other language definitions
WITH valsi_without_english AS (
    SELECT DISTINCT e.valsiid
    FROM etymology e
    WHERE NOT EXISTS (
        SELECT 1 
        FROM definitions d 
        WHERE d.valsiid = e.valsiid 
        AND d.langid = (SELECT langid FROM languages WHERE tag = 'en')
    )
),
ranked_other_definitions AS (
    SELECT 
        d.definitionid,
        d.valsiid,
        d.time,
        e.content AS etymology_content,
        ROW_NUMBER() OVER (PARTITION BY d.valsiid ORDER BY d.time ASC) AS rn
    FROM definitions d
    JOIN etymology e ON d.valsiid = e.valsiid
    JOIN valsi_without_english v ON v.valsiid = d.valsiid
)
UPDATE definitions d
SET etymology = r.etymology_content
FROM ranked_other_definitions r
WHERE d.definitionid = r.definitionid
AND r.rn = 1;

-- Finally, handle valsi that have etymologies but no definitions at all
INSERT INTO definitions (
    valsiid,
    langid,
    definition,
    etymology,
    userid,
    time,
    definitionnum
)
SELECT 
    e.valsiid,
    (SELECT langid FROM languages WHERE tag = 'en'),
    'No definition available', -- Default placeholder definition
    e.content,
    e.userid,
    e.time,
    1
FROM etymology e
WHERE NOT EXISTS (
    SELECT 1 FROM definitions d WHERE d.valsiid = e.valsiid
);

-- Create a backup of the etymology table
CREATE TABLE etymology_backup AS SELECT * FROM etymology;

-- Add a comment to indicate the backup was created during migration
DO $$
BEGIN
    EXECUTE 'COMMENT ON TABLE etymology_backup IS ''Backup of etymology table created during migration on ' || CURRENT_TIMESTAMP || '''';
END $$;

-- Don't drop the original table until verification
-- DROP TABLE etymology;

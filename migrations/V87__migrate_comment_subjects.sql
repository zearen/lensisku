-- Migrate existing subjects into content array
BEGIN;

-- Add header block as first element of content array where subject exists
UPDATE comments
SET content =
    CASE WHEN subject IS NOT NULL AND subject != '' THEN
        jsonb_insert(
            COALESCE(content, '[]'::jsonb),
            '{0}',
            jsonb_build_object('type', 'header', 'data', subject),
            false
        )
    ELSE
        content
    END;

COMMIT;
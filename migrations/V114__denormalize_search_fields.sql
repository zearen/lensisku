-- Add denormalized cached fields for fast search performance
-- This eliminates the need for JOINs to users, languages, valsitypes, and keywordmapping/natlangwords

-- Add cached display fields
ALTER TABLE definitions ADD COLUMN IF NOT EXISTS cached_username TEXT;
ALTER TABLE definitions ADD COLUMN IF NOT EXISTS cached_langrealname TEXT;
ALTER TABLE definitions ADD COLUMN IF NOT EXISTS cached_type_name TEXT;

-- Add cached search text field containing all searchable content
ALTER TABLE definitions ADD COLUMN IF NOT EXISTS cached_search_text TEXT;

-- Populate cached_search_text with all searchable content
-- This includes: word, rafsi, definition, notes, selmaho, and all glosswords/place keywords
UPDATE definitions
SET cached_search_text = LOWER(
    COALESCE((SELECT word FROM valsi WHERE valsiid = definitions.valsiid), '') || ' ' ||
    COALESCE((SELECT rafsi FROM valsi WHERE valsiid = definitions.valsiid), '') || ' ' ||
    COALESCE(definitions.definition, '') || ' ' ||
    COALESCE(definitions.notes, '') || ' ' ||
    COALESCE(definitions.selmaho, '') || ' ' ||
    COALESCE((
        SELECT string_agg(LOWER(n.word || ' ' || COALESCE(n.meaning, '')), ' ')
        FROM keywordmapping k
        JOIN natlangwords n ON k.natlangwordid = n.wordid
        WHERE k.definitionid = definitions.definitionid
    ), '')
);

-- Populate cached display fields
UPDATE definitions
SET 
    cached_username = (SELECT username FROM users WHERE userid = definitions.userid),
    cached_langrealname = (SELECT realname FROM languages WHERE langid = definitions.langid),
    cached_type_name = (
        SELECT vt.descriptor 
        FROM valsi v 
        JOIN valsitypes vt ON v.typeid = vt.typeid 
        WHERE v.valsiid = definitions.valsiid
    );

-- Create GIN index for fast text search on cached_search_text
CREATE INDEX IF NOT EXISTS idx_definitions_cached_search_text_gin 
ON definitions USING gin(cached_search_text gin_trgm_ops);

-- Covering index for fast search main query (excluding large text fields to avoid max size limit)
CREATE INDEX IF NOT EXISTS idx_definitions_fast_search_covering 
ON definitions(definitionid, valsiid, langid, selmaho, created_at, cached_username, cached_langrealname, cached_type_name)
WHERE definition != '';

-- Composite index for filtering (langid + valsiid)
CREATE INDEX IF NOT EXISTS idx_definitions_langid_valsiid 
ON definitions(langid, valsiid)
INCLUDE (definitionid);

-- Index for valsi filtering (minimal join needed)
CREATE INDEX IF NOT EXISTS idx_valsi_valsiid_source_langid_word 
ON valsi(valsiid, source_langid, word)
INCLUDE (rafsi, typeid);

-- Function to sync all cached fields
CREATE OR REPLACE FUNCTION sync_definition_cache_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- Update cached fields for the affected definition(s)
    IF TG_TABLE_NAME = 'definitions' THEN
        UPDATE definitions
        SET 
            cached_username = (SELECT username FROM users WHERE userid = definitions.userid),
            cached_langrealname = (SELECT realname FROM languages WHERE langid = definitions.langid),
            cached_type_name = (
                SELECT vt.descriptor 
                FROM valsi v 
                JOIN valsitypes vt ON v.typeid = vt.typeid 
                WHERE v.valsiid = definitions.valsiid
            ),
            cached_search_text = LOWER(
                COALESCE((SELECT word FROM valsi WHERE valsiid = definitions.valsiid), '') || ' ' ||
                COALESCE((SELECT rafsi FROM valsi WHERE valsiid = definitions.valsiid), '') || ' ' ||
                COALESCE(definitions.definition, '') || ' ' ||
                COALESCE(definitions.notes, '') || ' ' ||
                COALESCE(definitions.selmaho, '') || ' ' ||
                COALESCE((
                    SELECT string_agg(LOWER(n.word || ' ' || COALESCE(n.meaning, '')), ' ')
                    FROM keywordmapping k
                    JOIN natlangwords n ON k.natlangwordid = n.wordid
                    WHERE k.definitionid = definitions.definitionid
                ), '')
            )
        WHERE definitions.definitionid = COALESCE(NEW.definitionid, OLD.definitionid);
    ELSIF TG_TABLE_NAME = 'keywordmapping' THEN
        -- Update cached_search_text when keywords change
        UPDATE definitions
        SET cached_search_text = LOWER(
            COALESCE((SELECT word FROM valsi WHERE valsiid = definitions.valsiid), '') || ' ' ||
            COALESCE((SELECT rafsi FROM valsi WHERE valsiid = definitions.valsiid), '') || ' ' ||
            COALESCE(definitions.definition, '') || ' ' ||
            COALESCE(definitions.notes, '') || ' ' ||
            COALESCE(definitions.selmaho, '') || ' ' ||
            COALESCE((
                SELECT string_agg(LOWER(n.word || ' ' || COALESCE(n.meaning, '')), ' ')
                FROM keywordmapping k
                JOIN natlangwords n ON k.natlangwordid = n.wordid
                WHERE k.definitionid = definitions.definitionid
            ), '')
        )
        WHERE definitions.definitionid = COALESCE(NEW.definitionid, OLD.definitionid);
    ELSIF TG_TABLE_NAME = 'valsi' THEN
        -- Update cached_search_text when valsi word/rafsi changes
        UPDATE definitions
        SET cached_search_text = LOWER(
            COALESCE((SELECT word FROM valsi WHERE valsiid = definitions.valsiid), '') || ' ' ||
            COALESCE((SELECT rafsi FROM valsi WHERE valsiid = definitions.valsiid), '') || ' ' ||
            COALESCE(definitions.definition, '') || ' ' ||
            COALESCE(definitions.notes, '') || ' ' ||
            COALESCE(definitions.selmaho, '') || ' ' ||
            COALESCE((
                SELECT string_agg(LOWER(n.word || ' ' || COALESCE(n.meaning, '')), ' ')
                FROM keywordmapping k
                JOIN natlangwords n ON k.natlangwordid = n.wordid
                WHERE k.definitionid = definitions.definitionid
            ), '')
        )
        WHERE definitions.valsiid = COALESCE(NEW.valsiid, OLD.valsiid);
    ELSIF TG_TABLE_NAME = 'users' THEN
        -- Update cached_username when username changes
        UPDATE definitions
        SET cached_username = NEW.username
        WHERE definitions.userid = NEW.userid;
    ELSIF TG_TABLE_NAME = 'languages' THEN
        -- Update cached_langrealname when language name changes
        UPDATE definitions
        SET cached_langrealname = NEW.realname
        WHERE definitions.langid = NEW.langid;
    ELSIF TG_TABLE_NAME = 'valsitypes' THEN
        -- Update cached_type_name when type descriptor changes
        UPDATE definitions
        SET cached_type_name = NEW.descriptor
        FROM valsi v
        WHERE definitions.valsiid = v.valsiid
        AND v.typeid = NEW.typeid;
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger on definitions changes
DROP TRIGGER IF EXISTS trigger_sync_definition_cache ON definitions;
CREATE TRIGGER trigger_sync_definition_cache
AFTER INSERT OR UPDATE OF definition, notes, selmaho, userid, langid, valsiid
ON definitions
FOR EACH ROW EXECUTE FUNCTION sync_definition_cache_fields();

-- Trigger on keywordmapping changes (affects cached_search_text)
DROP TRIGGER IF EXISTS trigger_sync_definition_cache_from_keywords ON keywordmapping;
CREATE TRIGGER trigger_sync_definition_cache_from_keywords
AFTER INSERT OR UPDATE OR DELETE
ON keywordmapping
FOR EACH ROW EXECUTE FUNCTION sync_definition_cache_fields();

-- Trigger on valsi changes (affects cached_search_text)
DROP TRIGGER IF EXISTS trigger_sync_definition_cache_from_valsi ON valsi;
CREATE TRIGGER trigger_sync_definition_cache_from_valsi
AFTER UPDATE OF word, rafsi
ON valsi
FOR EACH ROW EXECUTE FUNCTION sync_definition_cache_fields();

-- Trigger on users changes (affects cached_username)
DROP TRIGGER IF EXISTS trigger_sync_definition_cache_from_users ON users;
CREATE TRIGGER trigger_sync_definition_cache_from_users
AFTER UPDATE OF username
ON users
FOR EACH ROW EXECUTE FUNCTION sync_definition_cache_fields();

-- Trigger on languages changes (affects cached_langrealname)
DROP TRIGGER IF EXISTS trigger_sync_definition_cache_from_languages ON languages;
CREATE TRIGGER trigger_sync_definition_cache_from_languages
AFTER UPDATE OF realname
ON languages
FOR EACH ROW EXECUTE FUNCTION sync_definition_cache_fields();

-- Trigger on valsitypes changes (affects cached_type_name)
DROP TRIGGER IF EXISTS trigger_sync_definition_cache_from_valsitypes ON valsitypes;
CREATE TRIGGER trigger_sync_definition_cache_from_valsitypes
AFTER UPDATE OF descriptor
ON valsitypes
FOR EACH ROW EXECUTE FUNCTION sync_definition_cache_fields();

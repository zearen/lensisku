-- Fix: In UPDATE ... FROM, the SET clause cannot reference the target table "d"
-- (PostgreSQL restriction). Use CTE to supply definition/notes/selmaho and
-- cached_* so SET never references d.

CREATE OR REPLACE FUNCTION sync_definition_cache_fields()
RETURNS TRIGGER AS $$
DECLARE
    target_definitionid INTEGER;
    target_valsiid INTEGER;
    target_natlangwordid INTEGER;
    kw_gloss TEXT := '';
    kw_text TEXT := '';
    v_word TEXT;
    v_rafsi TEXT;
    v_source_langid INTEGER;
    v_typeid INTEGER;
    v_type_name TEXT;
    u_username TEXT;
    l_realname TEXT;
    d_definition TEXT;
    d_notes TEXT;
    d_selmaho TEXT;
BEGIN
    -- Derive the ids we need based on the triggering table
    IF TG_TABLE_NAME = 'definitions' THEN
        target_definitionid := COALESCE(NEW.definitionid, OLD.definitionid);
        target_valsiid := COALESCE(NEW.valsiid, OLD.valsiid);
    ELSIF TG_TABLE_NAME = 'keywordmapping' THEN
        target_definitionid := COALESCE(NEW.definitionid, OLD.definitionid);
    ELSIF TG_TABLE_NAME = 'valsi' THEN
        target_valsiid := COALESCE(NEW.valsiid, OLD.valsiid);
    ELSIF TG_TABLE_NAME = 'natlangwords' THEN
        target_natlangwordid := COALESCE(NEW.wordid, OLD.wordid);
    END IF;

    -- Helper: load keyword aggregates when we have a specific definition id
    IF target_definitionid IS NOT NULL THEN
        SELECT COALESCE(string_agg(LOWER(n.word), ' ' ORDER BY n.word), ''),
               COALESCE(string_agg(LOWER(n.word || ' ' || COALESCE(n.meaning, '')), ' '), '')
        INTO kw_gloss, kw_text
        FROM keywordmapping k
        JOIN natlangwords n ON k.natlangwordid = n.wordid
        WHERE k.definitionid = target_definitionid;
    END IF;

    -- Update cached fields for the affected definition(s)
    IF TG_TABLE_NAME = 'definitions' THEN
        SELECT d.definition, d.notes, d.selmaho,
               v.word, v.rafsi, v.source_langid, v.typeid,
               vt.descriptor, u.username, l.realname
        INTO d_definition, d_notes, d_selmaho,
             v_word, v_rafsi, v_source_langid, v_typeid,
             v_type_name, u_username, l_realname
        FROM definitions d
        JOIN valsi v ON d.valsiid = v.valsiid
        JOIN users u ON d.userid = u.userid
        JOIN languages l ON d.langid = l.langid
        JOIN valsitypes vt ON v.typeid = vt.typeid
        WHERE d.definitionid = target_definitionid;

        UPDATE definitions
        SET
            cached_username = u_username,
            cached_langrealname = l_realname,
            cached_type_name = v_type_name,
            cached_valsiword = v_word,
            cached_rafsi = v_rafsi,
            cached_source_langid = v_source_langid,
            cached_typeid = v_typeid,
            cached_glosswords = kw_gloss,
            cached_search_text = LOWER(
                COALESCE(v_word, '') || ' ' ||
                COALESCE(v_rafsi, '') || ' ' ||
                COALESCE(d_definition, '') || ' ' ||
                COALESCE(d_notes, '') || ' ' ||
                COALESCE(d_selmaho, '') || ' ' ||
                COALESCE(kw_text, '')
            )
        WHERE definitionid = target_definitionid;

    ELSIF TG_TABLE_NAME = 'keywordmapping' THEN
        -- Update cached_glosswords and cached_search_text when keywords change
        UPDATE definitions d
        SET
            cached_glosswords = kw_gloss,
            cached_search_text = LOWER(
                COALESCE(d.cached_valsiword, '') || ' ' ||
                COALESCE(d.cached_rafsi, '') || ' ' ||
                COALESCE(d.definition, '') || ' ' ||
                COALESCE(d.notes, '') || ' ' ||
                COALESCE(d.selmaho, '') || ' ' ||
                COALESCE(kw_text, '')
            )
        WHERE d.definitionid = target_definitionid;

    ELSIF TG_TABLE_NAME = 'valsi' THEN
        -- Update cached valsi fields and cached_search_text when valsi changes.
        -- Do not reference target table "d" in SET when USING FROM (Postgres rule).
        WITH keyword_agg AS (
            SELECT k.definitionid,
                   MAX(d2.definition) AS def_text,
                   MAX(d2.notes) AS notes_text,
                   MAX(d2.selmaho) AS selmaho_text,
                   string_agg(LOWER(n.word), ' ' ORDER BY n.word) FILTER (WHERE k.place = 0) AS glosswords,
                   string_agg(LOWER(n.word || ' ' || COALESCE(n.meaning, '')), ' ') AS keyword_text
            FROM keywordmapping k
            JOIN natlangwords n ON k.natlangwordid = n.wordid
            JOIN definitions d2 ON d2.definitionid = k.definitionid
            WHERE d2.valsiid = target_valsiid
            GROUP BY k.definitionid
        )
        UPDATE definitions d
        SET
            cached_valsiword = v.word,
            cached_rafsi = v.rafsi,
            cached_source_langid = v.source_langid,
            cached_typeid = v.typeid,
            cached_type_name = vt.descriptor,
            cached_glosswords = COALESCE(ka.glosswords, ''),
            cached_search_text = LOWER(
                COALESCE(v.word, '') || ' ' ||
                COALESCE(v.rafsi, '') || ' ' ||
                COALESCE(ka.def_text, '') || ' ' ||
                COALESCE(ka.notes_text, '') || ' ' ||
                COALESCE(ka.selmaho_text, '') || ' ' ||
                COALESCE(ka.keyword_text, '')
            )
        FROM valsi v
        JOIN valsitypes vt ON v.typeid = vt.typeid
        LEFT JOIN keyword_agg ka ON ka.definitionid = d.definitionid
        WHERE d.valsiid = target_valsiid
        AND d.valsiid = v.valsiid;

    ELSIF TG_TABLE_NAME = 'users' THEN
        -- Update cached_username when username changes
        UPDATE definitions d
        SET cached_username = NEW.username
        WHERE d.userid = NEW.userid;

    ELSIF TG_TABLE_NAME = 'languages' THEN
        -- Update cached_langrealname when language name changes
        UPDATE definitions d
        SET cached_langrealname = NEW.realname
        WHERE d.langid = NEW.langid;

    ELSIF TG_TABLE_NAME = 'valsitypes' THEN
        -- Update cached_type_name and cached_typeid when type descriptor changes
        UPDATE definitions d
        SET
            cached_type_name = NEW.descriptor,
            cached_typeid = NEW.typeid
        WHERE d.cached_typeid = NEW.typeid;

    ELSIF TG_TABLE_NAME = 'natlangwords' THEN
        -- Update cached_glosswords and cached_search_text when natlangwords change.
        -- Do not reference target table "d" in SET when USING FROM (Postgres rule).
        WITH affected AS (
            SELECT DISTINCT k.definitionid
            FROM keywordmapping k
            WHERE k.natlangwordid = target_natlangwordid
        ),
        keyword_agg AS (
            SELECT k.definitionid,
                   MAX(d2.cached_valsiword) AS cached_valsiword,
                   MAX(d2.cached_rafsi) AS cached_rafsi,
                   MAX(d2.definition) AS def_text,
                   MAX(d2.notes) AS notes_text,
                   MAX(d2.selmaho) AS selmaho_text,
                   string_agg(LOWER(n.word), ' ' ORDER BY n.word) FILTER (WHERE k.place = 0) AS glosswords,
                   string_agg(LOWER(n.word || ' ' || COALESCE(n.meaning, '')), ' ') AS keyword_text
            FROM keywordmapping k
            JOIN natlangwords n ON k.natlangwordid = n.wordid
            JOIN definitions d2 ON d2.definitionid = k.definitionid
            JOIN affected a ON a.definitionid = k.definitionid
            GROUP BY k.definitionid
        )
        UPDATE definitions d
        SET
            cached_glosswords = COALESCE(ka.glosswords, ''),
            cached_search_text = LOWER(
                COALESCE(ka.cached_valsiword, '') || ' ' ||
                COALESCE(ka.cached_rafsi, '') || ' ' ||
                COALESCE(ka.def_text, '') || ' ' ||
                COALESCE(ka.notes_text, '') || ' ' ||
                COALESCE(ka.selmaho_text, '') || ' ' ||
                COALESCE(ka.keyword_text, '')
            )
        FROM keyword_agg ka
        WHERE d.definitionid = ka.definitionid;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

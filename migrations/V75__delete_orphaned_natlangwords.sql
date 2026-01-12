-- Delete orphaned natlangwords not referenced by other tables
CREATE FUNCTION public.delete_orphaned_natlangwords() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM natlangwords n
    WHERE NOT EXISTS (
        SELECT 1 FROM threads t WHERE t.natlangwordid = n.wordid
    )
    AND NOT EXISTS (
        SELECT 1 FROM natlangwordvotes v WHERE v.natlangwordid = n.wordid
    )
    AND NOT EXISTS (
        SELECT 1 FROM keywordmapping k WHERE k.natlangwordid = n.wordid
    );
END;
$$;

-- Trigger function to handle cleanup and reload
CREATE FUNCTION public.trigger_cleanup_natlangwords() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM public.delete_orphaned_natlangwords();
    PERFORM public.reload_natlangwordbestplaces();
    RETURN NULL;
END;
$$;

CREATE TRIGGER natlangwords_cleanup_trigger
AFTER INSERT OR UPDATE ON natlangwords
FOR EACH ROW EXECUTE FUNCTION public.trigger_cleanup_natlangwords();

-- Run initial cleanup
SELECT public.delete_orphaned_natlangwords();

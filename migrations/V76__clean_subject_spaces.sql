CREATE OR REPLACE FUNCTION clean_subject(subject text) RETURNS text AS $$
DECLARE
    clean text;
    modified boolean;
    bracket_start int;
    bracket_end int;
BEGIN
    clean := subject;
    
    LOOP
        modified := false;
        clean := trim(clean);
        
        IF lower(substr(clean, 1, 3)) = 're:' THEN
            clean := trim(substr(clean, 4));
            modified := true;
            CONTINUE;
        END IF;
        
        bracket_start := position('[' in clean);
        IF bracket_start > 0 THEN
            bracket_end := position(']' in substr(clean, bracket_start));
            IF bracket_end > 0 THEN
                clean := trim(substr(clean, 1, bracket_start - 1) || 
                            substr(clean, bracket_start + bracket_end));
                modified := true;
                CONTINUE;
            END IF;
        END IF;
        
        EXIT WHEN NOT modified;
    END LOOP;

    -- Replace multiple spaces with single space
    clean := regexp_replace(clean, '\s+', ' ', 'g');

    RETURN trim(clean);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

UPDATE messages 
SET cleaned_subject = clean_subject(subject);

CREATE INDEX IF NOT EXISTS idx_messages_cleaned_subject ON messages(cleaned_subject);

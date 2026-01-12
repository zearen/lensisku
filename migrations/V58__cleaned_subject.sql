ALTER TABLE messages ADD COLUMN cleaned_subject text;

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

    RETURN trim(clean);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION update_cleaned_subject() RETURNS trigger AS $$
BEGIN
    NEW.cleaned_subject := clean_subject(NEW.subject);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_cleaned_subject 
    BEFORE INSERT OR UPDATE ON messages
    FOR EACH ROW 
    EXECUTE FUNCTION update_cleaned_subject();

UPDATE messages 
SET cleaned_subject = clean_subject(subject);

CREATE INDEX idx_messages_cleaned_subject ON messages(cleaned_subject);
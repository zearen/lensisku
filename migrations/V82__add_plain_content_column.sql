-- Add new plain_content column
ALTER TABLE comments ADD COLUMN plain_content TEXT;

-- Create trigger function to update plain_content
CREATE OR REPLACE FUNCTION extract_plain_content()
 RETURNS TRIGGER AS $$
 DECLARE
     element JSONB;
     result TEXT := '';
 BEGIN
     IF NEW.content IS NULL THEN
         NEW.plain_content := '';
         RETURN NEW;
     END IF;

     FOR element IN SELECT * FROM jsonb_array_elements(NEW.content)
    LOOP
        IF element->>'type' = 'text' THEN
            result := result || (element->>'data') || ' ';
        END IF;
     END LOOP;

     NEW.plain_content := TRIM(result);
     RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update plain_content automatically
CREATE TRIGGER update_plain_content
BEFORE INSERT OR UPDATE OF content ON comments
FOR EACH ROW
EXECUTE FUNCTION extract_plain_content();

-- Backfill existing data
UPDATE comments
SET plain_content = (
    SELECT TRIM(STRING_AGG(element->>'data', ' '))
    FROM jsonb_array_elements(content) AS element
    WHERE element->>'type' = 'text'
);

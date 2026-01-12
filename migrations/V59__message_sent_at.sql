CREATE OR REPLACE FUNCTION parse_email_date(date_text text) 
RETURNS timestamptz AS $$
DECLARE
  cleaned_date text;
BEGIN
  IF date_text IS NULL OR date_text = '' THEN
      RETURN NULL;
  END IF;

  -- Remove timezone names in parentheses
  cleaned_date := regexp_replace(date_text, '\s*\([A-Z]+\)', '', 'g');
  
  -- Convert EST/EDT to -0500/-0400
  cleaned_date := regexp_replace(cleaned_date, '\sEST\s*$', ' -0500', 'g');
  cleaned_date := regexp_replace(cleaned_date, '\sEDT\s*$', ' -0400', 'g');
  
  -- Parse as timestamp with timezone
  RETURN cleaned_date::timestamptz;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Migration
ALTER TABLE messages ADD COLUMN sent_at timestamptz;
UPDATE messages SET sent_at = parse_email_date(date) WHERE date IS NOT NULL AND date != '';
UPDATE messages SET sent_at = NOW() WHERE sent_at IS NULL;
ALTER TABLE messages ALTER COLUMN sent_at SET NOT NULL;

CREATE OR REPLACE FUNCTION set_message_sent_at()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.date IS NOT NULL AND NEW.sent_at IS NULL THEN
      NEW.sent_at := parse_email_date(NEW.date);
  END IF;
  IF NEW.sent_at IS NULL THEN
      NEW.sent_at := NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER message_sent_at_trigger
BEFORE INSERT OR UPDATE ON messages
FOR EACH ROW
EXECUTE FUNCTION set_message_sent_at();
BEGIN;

ALTER TABLE messages DROP CONSTRAINT unique_message_id;
ALTER TABLE messages ADD CONSTRAINT unique_file_path UNIQUE (file_path);

COMMIT;

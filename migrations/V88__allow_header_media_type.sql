ALTER TABLE comment_media DROP CONSTRAINT valid_media_check;
ALTER TABLE comment_media ADD CONSTRAINT valid_media_check CHECK (
    (media_type = 'image' AND media_data IS NOT NULL) OR
    (media_type = 'text' AND text_content IS NOT NULL) OR 
    (media_type = 'header' AND text_content IS NOT NULL)
);

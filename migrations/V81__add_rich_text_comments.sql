-- Temporarily drop dependent view
DROP VIEW IF EXISTS convenientcomments;

-- Migrate existing comments to new format
ALTER TABLE comments ALTER COLUMN content TYPE jsonb USING jsonb_build_array(jsonb_build_object('type', 'text', 'data', content));

-- Recreate view with updated column type
CREATE VIEW convenientcomments AS
SELECT c.commentid,
    c.threadid,
    c.parentid,
    c.userid,
    u.username,
    u.realname,
    c."time",
    c.subject,
    c.content,
    c.commentnum,
    cc.total_reactions,
    cc.total_replies,
    t.valsiid,
    t.definitionid
FROM (((public.comments c
    JOIN public.users u ON ((c.userid = u.userid)))
    JOIN public.threads t ON ((c.threadid = t.threadid)))
    LEFT JOIN public.comment_counters cc ON ((c.commentid = cc.comment_id)));

-- Add media support
CREATE TABLE public.comment_media (
    media_id SERIAL PRIMARY KEY,
    comment_id integer REFERENCES comments(commentid) ON DELETE CASCADE,
    media_type text NOT NULL,
    media_data bytea,
    text_content text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_media_check CHECK (
        (media_type = 'image' AND media_data IS NOT NULL) OR
        (media_type = 'text' AND text_content IS NOT NULL)
    )
);

CREATE INDEX idx_comment_media_comment ON comment_media(comment_id);
CREATE INDEX idx_comment_media_type ON comment_media(media_type);

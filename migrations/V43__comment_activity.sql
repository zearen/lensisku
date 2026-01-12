-- Create unified counters table for comments
CREATE TABLE IF NOT EXISTS comment_activity_counters (
    comment_id INTEGER PRIMARY KEY REFERENCES comments(commentid) ON DELETE CASCADE,
    total_likes BIGINT NOT NULL DEFAULT 0,
    total_bookmarks BIGINT NOT NULL DEFAULT 0,
    total_replies BIGINT NOT NULL DEFAULT 0,
    total_reactions BIGINT NOT NULL DEFAULT 0,
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes if they don't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_comment_counters_activity') THEN
        CREATE INDEX idx_comment_counters_activity ON comment_activity_counters(last_activity_at DESC);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_comment_counters_reactions') THEN
        CREATE INDEX idx_comment_counters_reactions ON comment_activity_counters(total_reactions DESC);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_comment_counters_bookmarks') THEN
        CREATE INDEX idx_comment_counters_bookmarks ON comment_activity_counters(total_bookmarks DESC);
    END IF;
END $$;

-- Create trigger function to update last_activity timestamp
CREATE OR REPLACE FUNCTION update_comment_activity_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_activity_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_comment_activity_timestamp ON comment_activity_counters;
CREATE TRIGGER update_comment_activity_timestamp
    BEFORE UPDATE ON comment_activity_counters
    FOR EACH ROW
    EXECUTE FUNCTION update_comment_activity_timestamp();

-- Populate counters table from existing data
INSERT INTO comment_activity_counters (
    comment_id, 
    total_likes,
    total_bookmarks,
    total_reactions,
    total_replies
)
SELECT 
    c.commentid,
    COALESCE(likes.count, 0),
    COALESCE(bookmarks.count, 0),
    COALESCE(reactions.count, 0),
    COALESCE(replies.count, 0)
FROM comments c
LEFT JOIN (
    SELECT comment_id, COUNT(*) as count
    FROM comment_likes
    GROUP BY comment_id
) likes ON c.commentid = likes.comment_id
LEFT JOIN (
    SELECT comment_id, COUNT(*) as count
    FROM comment_bookmarks
    GROUP BY comment_id
) bookmarks ON c.commentid = bookmarks.comment_id
LEFT JOIN (
    SELECT comment_id, COUNT(*) as count
    FROM comment_reactions
    GROUP BY comment_id
) reactions ON c.commentid = reactions.comment_id
LEFT JOIN (
    SELECT parentid, COUNT(*) as count
    FROM comments
    WHERE parentid > 0
    GROUP BY parentid
) replies ON c.commentid = replies.parentid
ON CONFLICT (comment_id) DO NOTHING;
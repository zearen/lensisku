-- Add new columns to threads table
ALTER TABLE threads 
    ADD COLUMN IF NOT EXISTS last_comment_id INTEGER REFERENCES comments(commentid),
    ADD COLUMN IF NOT EXISTS last_comment_user_id INTEGER REFERENCES users(userid),
    ADD COLUMN IF NOT EXISTS last_comment_time INTEGER,
    ADD COLUMN IF NOT EXISTS last_comment_subject TEXT,
    ADD COLUMN IF NOT EXISTS last_comment_content JSONB,
    ADD COLUMN IF NOT EXISTS total_comments INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS creator_user_id INTEGER REFERENCES users(userid),
    ADD COLUMN IF NOT EXISTS creator_username VARCHAR(64);

-- Create function to update thread stats
CREATE OR REPLACE FUNCTION update_thread_stats() RETURNS TRIGGER AS $$
BEGIN
    -- Update stats for both old and new thread IDs (for comment moves)
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        UPDATE threads SET
            last_comment_id = (SELECT commentid FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_user_id = (SELECT userid FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_time = (SELECT time FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_subject = (SELECT subject FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_content = (SELECT content FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            total_comments = (SELECT COUNT(*) FROM comments WHERE threadid = OLD.threadid),
            first_comment_subject = (SELECT subject FROM comments WHERE threadid = OLD.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            first_comment_content = (SELECT content FROM comments WHERE threadid = OLD.threadid ORDER BY time ASC, commentid ASC LIMIT 1)
        WHERE threadid = OLD.threadid;
    END IF;
    
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        UPDATE threads SET
            last_comment_id = (SELECT commentid FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_user_id = (SELECT userid FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_time = (SELECT time FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_subject = (SELECT subject FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_content = (SELECT content FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            total_comments = (SELECT COUNT(*) FROM comments WHERE threadid = NEW.threadid),
            first_comment_subject = (SELECT subject FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            first_comment_content = (SELECT content FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1)
        WHERE threadid = NEW.threadid;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE OR REPLACE TRIGGER comment_stats_trigger
AFTER INSERT OR UPDATE OR DELETE ON comments
FOR EACH ROW EXECUTE FUNCTION update_thread_stats();

-- Backfill creator information for existing threads
WITH first_comments AS (
    SELECT DISTINCT ON (t.threadid)
        t.threadid,
        c.userid,
        u.username
    FROM threads t
    JOIN comments c ON t.threadid = c.threadid
    JOIN users u ON c.userid = u.userid
    ORDER BY t.threadid, c.time ASC, c.commentid ASC
)
UPDATE threads t
SET 
    creator_user_id = fc.userid,
    creator_username = fc.username
FROM first_comments fc
WHERE t.threadid = fc.threadid;

-- Backfill all thread stats columns using latest comments data
WITH thread_stats AS (
    SELECT 
        t.threadid,
        -- Latest comment details
        latest.commentid AS last_comment_id,
        latest.userid AS last_comment_user_id,
        latest.time AS last_comment_time,
        latest.subject AS last_comment_subject,
        latest.content AS last_comment_content,
        COUNT(c.commentid) AS total_comments,
        -- Creator details from first comment
        first_comment.userid AS creator_user_id,
        first_comment.username AS creator_username
    FROM threads t
    JOIN comments c ON t.threadid = c.threadid
    -- Get latest comment per thread
    LEFT JOIN LATERAL (
        SELECT commentid, time, subject, content, userid 
        FROM comments 
        WHERE threadid = t.threadid 
        ORDER BY time DESC, commentid DESC 
        LIMIT 1
    ) latest ON true
    -- Get first comment per thread
    LEFT JOIN LATERAL (
        SELECT c.userid, u.username 
        FROM comments c
        JOIN users u ON c.userid = u.userid
        WHERE threadid = t.threadid 
        ORDER BY time ASC, commentid ASC 
        LIMIT 1
    ) first_comment ON true
    GROUP BY t.threadid, latest.commentid, latest.time, latest.subject, 
             latest.content, latest.userid, first_comment.userid, first_comment.username
)
UPDATE threads t
SET
    last_comment_id = ts.last_comment_id,
    last_comment_user_id = ts.last_comment_user_id,
    last_comment_time = ts.last_comment_time,
    last_comment_subject = ts.last_comment_subject,
    last_comment_content = ts.last_comment_content,
    total_comments = ts.total_comments,
    creator_user_id = ts.creator_user_id,
    creator_username = ts.creator_username
FROM thread_stats ts
WHERE t.threadid = ts.threadid;

-- Add first comment metadata columns
ALTER TABLE threads 
    ADD COLUMN IF NOT EXISTS first_comment_subject TEXT,
    ADD COLUMN IF NOT EXISTS first_comment_content JSONB;

-- Update trigger function to maintain first comment data
CREATE OR REPLACE FUNCTION update_thread_stats() RETURNS TRIGGER AS $$
BEGIN
    -- Update stats for both old and new thread IDs (for comment moves)
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        UPDATE threads SET
            first_comment_subject = (SELECT subject FROM comments WHERE threadid = OLD.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            first_comment_content = (SELECT content FROM comments WHERE threadid = OLD.threadid ORDER BY time ASC, commentid ASC LIMIT 1)
        WHERE threadid = OLD.threadid;
    END IF;
    
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        UPDATE threads SET
            first_comment_subject = (SELECT subject FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            first_comment_content = (SELECT content FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1)
        WHERE threadid = NEW.threadid;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Backfill existing first comment data
WITH first_comments AS (
    SELECT DISTINCT ON (threadid)
        threadid,
        subject,
        content
    FROM comments
    ORDER BY threadid, time ASC, commentid ASC
)
UPDATE threads t
SET 
    first_comment_subject = fc.subject,
    first_comment_content = fc.content
FROM first_comments fc
WHERE t.threadid = fc.threadid;


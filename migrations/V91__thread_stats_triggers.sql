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
            first_comment_content = (SELECT content FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            creator_user_id = (SELECT userid FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            creator_username = (SELECT username FROM users WHERE userid = (SELECT userid FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1))
        WHERE threadid = NEW.threadid;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE OR REPLACE TRIGGER comment_stats_trigger
AFTER INSERT OR UPDATE OR DELETE ON comments
FOR EACH ROW EXECUTE FUNCTION update_thread_stats();

-- Combined backfill of all thread stats in single CTE
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
        -- First comment details
        first_comment.userid AS creator_user_id,
        first_comment.username AS creator_username,
        first_comment.subject AS first_comment_subject,
        first_comment.content AS first_comment_content
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
        SELECT c.userid, u.username, c.subject, c.content
        FROM comments c
        JOIN users u ON c.userid = u.userid
        WHERE threadid = t.threadid 
        ORDER BY time ASC, commentid ASC 
        LIMIT 1
    ) first_comment ON true
    GROUP BY t.threadid, latest.commentid, latest.time, latest.subject, 
             latest.content, latest.userid, first_comment.userid, first_comment.username,
             first_comment.subject, first_comment.content
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
    creator_username = ts.creator_username,
    first_comment_subject = ts.first_comment_subject,
    first_comment_content = ts.first_comment_content
FROM thread_stats ts
WHERE t.threadid = ts.threadid;



-- Create comment counters table to track likes and replies
CREATE TABLE IF NOT EXISTS comment_counters (
    comment_id INTEGER PRIMARY KEY REFERENCES comments(commentid) ON DELETE CASCADE,
    total_likes BIGINT NOT NULL DEFAULT 0,
    total_replies BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create comment likes table
CREATE TABLE IF NOT EXISTS comment_likes (
    comment_id INTEGER NOT NULL REFERENCES comments(commentid) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(userid) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (comment_id, user_id)
);

-- Create comment bookmarks table
CREATE TABLE IF NOT EXISTS comment_bookmarks (
    comment_id INTEGER NOT NULL REFERENCES comments(commentid) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(userid) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (comment_id, user_id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_comment_likes_user ON comment_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_comment_likes_comment ON comment_likes(comment_id);
CREATE INDEX IF NOT EXISTS idx_comment_bookmarks_user ON comment_bookmarks(user_id);
CREATE INDEX IF NOT EXISTS idx_comment_bookmarks_comment ON comment_bookmarks(comment_id);

-- Create trigger to update comments counter updated_at timestamp
CREATE OR REPLACE FUNCTION update_comment_counter_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_comment_counter_timestamp
    BEFORE UPDATE ON comment_counters
    FOR EACH ROW
    EXECUTE FUNCTION update_comment_counter_timestamp();

-- Create or replace view for convenient comment access
CREATE OR REPLACE VIEW convenientcomments AS
SELECT 
    c.commentid,
    c.threadid,
    c.parentid,
    c.userid,
    u.username,
    u.realname,
    c.time,
    c.subject,
    c.content,
    c.commentnum,
    cc.total_likes,
    cc.total_replies
FROM 
    comments c
    JOIN users u ON c.userid = u.userid
    LEFT JOIN comment_counters cc ON c.commentid = cc.comment_id;

-- Create comment opinions table
CREATE TABLE IF NOT EXISTS comment_opinions (
    id BIGSERIAL PRIMARY KEY,
    comment_id INTEGER NOT NULL REFERENCES comments(commentid) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(userid) ON DELETE CASCADE,
    opinion VARCHAR(12) NOT NULL,
    votes INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Only allow one instance of an opinion per comment
    UNIQUE(comment_id, opinion)
);

-- Create opinion votes table
CREATE TABLE IF NOT EXISTS comment_opinion_votes (
    opinion_id BIGINT NOT NULL REFERENCES comment_opinions(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(userid) ON DELETE CASCADE,
    comment_id INTEGER NOT NULL REFERENCES comments(commentid) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- One vote per user per opinion
    PRIMARY KEY (user_id, comment_id, opinion_id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_comment_opinions_comment ON comment_opinions(comment_id);
CREATE INDEX IF NOT EXISTS idx_comment_opinions_user ON comment_opinions(user_id);
CREATE INDEX IF NOT EXISTS idx_comment_opinion_votes_opinion ON comment_opinion_votes(opinion_id);
CREATE INDEX IF NOT EXISTS idx_comment_opinion_votes_user ON comment_opinion_votes(user_id);

-- Create unified counters table for comments
CREATE TABLE IF NOT EXISTS comment_activity_counters (
    comment_id INTEGER PRIMARY KEY REFERENCES comments(commentid) ON DELETE CASCADE,
    total_likes BIGINT NOT NULL DEFAULT 0,
    total_bookmarks BIGINT NOT NULL DEFAULT 0,
    total_replies BIGINT NOT NULL DEFAULT 0,
    total_opinions BIGINT NOT NULL DEFAULT 0,
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX idx_comment_counters_likes ON comment_activity_counters(total_likes DESC);
CREATE INDEX idx_comment_counters_activity ON comment_activity_counters(last_activity_at DESC);

-- Create trigger function to update last_activity timestamp
CREATE OR REPLACE FUNCTION update_comment_activity_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_activity_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_comment_activity_timestamp
    BEFORE UPDATE ON comment_activity_counters
    FOR EACH ROW
    EXECUTE FUNCTION update_comment_activity_timestamp();

-- Populate counters table from existing data
INSERT INTO comment_activity_counters (comment_id, total_likes, total_bookmarks, total_replies)
SELECT 
    c.commentid,
    COALESCE(likes.like_count, 0) as total_likes,
    COALESCE(bookmarks.bookmark_count, 0) as total_bookmarks,
    COALESCE((
        SELECT COUNT(*)
        FROM comments replies
        WHERE replies.parentid = c.commentid
    ), 0) as total_replies
FROM comments c
LEFT JOIN (
    SELECT comment_id, COUNT(*) as like_count
    FROM comment_likes
    GROUP BY comment_id
) likes ON c.commentid = likes.comment_id
LEFT JOIN (
    SELECT comment_id, COUNT(*) as bookmark_count 
    FROM comment_bookmarks
    GROUP BY comment_id
) bookmarks ON c.commentid = bookmarks.comment_id
ON CONFLICT (comment_id) DO NOTHING;

-- Create trigger to maintain reply counts
CREATE OR REPLACE FUNCTION update_comment_reply_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.parentid IS NOT NULL THEN
            UPDATE comment_activity_counters
            SET total_replies = total_replies + 1
            WHERE comment_id = NEW.parentid;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.parentid IS NOT NULL THEN
            UPDATE comment_activity_counters
            SET total_replies = total_replies - 1
            WHERE comment_id = OLD.parentid;
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER maintain_comment_reply_count
    AFTER INSERT OR DELETE ON comments
    FOR EACH ROW
    EXECUTE FUNCTION update_comment_reply_count();

-- Create function to update activity counters
CREATE OR REPLACE FUNCTION update_comment_counter(
    p_comment_id INTEGER,
    p_counter_type TEXT,
    p_increment BOOLEAN
) RETURNS VOID AS $$
DECLARE
    v_amount INTEGER;
BEGIN
    v_amount := CASE WHEN p_increment THEN 1 ELSE -1 END;
    
    EXECUTE format('
        INSERT INTO comment_activity_counters (comment_id, total_%I)
        VALUES ($1, $2)
        ON CONFLICT (comment_id) 
        DO UPDATE SET total_%I = comment_activity_counters.total_%I + $2',
        p_counter_type, p_counter_type, p_counter_type
    ) USING p_comment_id, v_amount;
END;
$$ LANGUAGE plpgsql;
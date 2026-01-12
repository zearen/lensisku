-- Create reactions table
CREATE TABLE comment_reactions (
    id SERIAL PRIMARY KEY,
    comment_id INTEGER NOT NULL REFERENCES comments(commentid) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(userid) ON DELETE CASCADE,
    reaction VARCHAR(32) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Each user can have one instance of each reaction type per comment
    UNIQUE(comment_id, user_id, reaction)
);

-- Create index for faster lookups
CREATE INDEX idx_comment_reactions_comment ON comment_reactions(comment_id);
CREATE INDEX idx_comment_reactions_user ON comment_reactions(user_id);

-- Add reactions count to activity counters
ALTER TABLE comment_activity_counters
ADD COLUMN total_reactions INTEGER NOT NULL DEFAULT 0;

-- Create function to update reaction counts
CREATE OR REPLACE FUNCTION update_reaction_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE comment_activity_counters
        SET total_reactions = total_reactions + 1,
            last_activity_at = CURRENT_TIMESTAMP
        WHERE comment_id = NEW.comment_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE comment_activity_counters
        SET total_reactions = total_reactions - 1,
            last_activity_at = CURRENT_TIMESTAMP
        WHERE comment_id = OLD.comment_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for maintaining reaction counts
CREATE TRIGGER update_reaction_count
    AFTER INSERT OR DELETE ON comment_reactions
    FOR EACH ROW
    EXECUTE FUNCTION update_reaction_count();
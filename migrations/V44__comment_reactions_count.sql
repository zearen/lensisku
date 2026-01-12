CREATE OR REPLACE FUNCTION update_reaction_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Only increment if this is the user's first reaction for this comment
        IF NOT EXISTS (
            SELECT 1 
            FROM comment_reactions 
            WHERE comment_id = NEW.comment_id 
            AND user_id = NEW.user_id 
            AND id != NEW.id
        ) THEN
            UPDATE comment_activity_counters
            SET total_reactions = total_reactions + 1,
                last_activity_at = CURRENT_TIMESTAMP
            WHERE comment_id = NEW.comment_id;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        -- Only decrement if this was user's last reaction
        -- Note: We don't need to exclude OLD record as it's already deleted
        IF NOT EXISTS (
            SELECT 1 
            FROM comment_reactions 
            WHERE comment_id = OLD.comment_id 
            AND user_id = OLD.user_id
        ) THEN
            UPDATE comment_activity_counters
            SET total_reactions = total_reactions - 1,
                last_activity_at = CURRENT_TIMESTAMP
            WHERE comment_id = OLD.comment_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
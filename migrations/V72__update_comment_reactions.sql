-- Update comment_counters table
ALTER TABLE comment_counters RENAME COLUMN total_likes TO total_reactions;

-- Rename column in convenientcomments view
ALTER VIEW convenientcomments RENAME COLUMN total_likes TO total_reactions;

-- Update trigger function
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

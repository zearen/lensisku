CREATE OR REPLACE FUNCTION check_reaction_limit(p_user_id INT, p_comment_id INT) 
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (
        SELECT COALESCE(reaction_count, 0) < 5
        FROM user_reaction_counts
        WHERE user_id = p_user_id AND comment_id = p_comment_id
        UNION ALL
        SELECT true 
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql;
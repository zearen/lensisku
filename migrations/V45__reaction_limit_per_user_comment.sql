-- Create a view to track reaction counts per user and comment
CREATE MATERIALIZED VIEW user_reaction_counts AS
SELECT user_id, comment_id, COUNT(*) as reaction_count
FROM comment_reactions
GROUP BY user_id, comment_id;

CREATE UNIQUE INDEX user_reaction_counts_idx ON user_reaction_counts(user_id, comment_id);

-- Function to refresh the materialized view
CREATE OR REPLACE FUNCTION refresh_reaction_counts()
RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY user_reaction_counts;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger to refresh counts
CREATE TRIGGER update_reaction_counts
    AFTER INSERT OR DELETE ON comment_reactions
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_reaction_counts();

-- Function to check reaction limit
CREATE OR REPLACE FUNCTION check_reaction_limit(p_user_id INT, p_comment_id INT) 
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (
        SELECT COALESCE(reaction_count, 0) < 5
        FROM user_reaction_counts
        WHERE user_id = p_user_id AND comment_id = p_comment_id
    );
END;
$$ LANGUAGE plpgsql;
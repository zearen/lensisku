CREATE TABLE follows (
    follower_id INTEGER REFERENCES users(userid),
    followee_id INTEGER REFERENCES users(userid),
    follow_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id != followee_id)
);

-- Add followers count to users table
ALTER TABLE users 
ADD COLUMN followers INTEGER NOT NULL DEFAULT 0;

-- Create function to maintain followers count
CREATE OR REPLACE FUNCTION update_followers_count() 
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET followers = followers + 1 
        WHERE userid = NEW.followee_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users SET followers = followers - 1 
        WHERE userid = OLD.followee_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update followers count
CREATE TRIGGER update_followers_count
    AFTER INSERT OR DELETE ON follows
    FOR EACH ROW
    EXECUTE FUNCTION update_followers_count();
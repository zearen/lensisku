-- Create hashtags table
CREATE TABLE IF NOT EXISTS hashtags (
    id SERIAL PRIMARY KEY,
    tag VARCHAR(255) UNIQUE NOT NULL
);

-- Create mapping table between posts and hashtags
CREATE TABLE IF NOT EXISTS post_hashtags (
    post_id INTEGER REFERENCES comments(commentid) ON DELETE CASCADE,
    hashtag_id INTEGER REFERENCES hashtags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id, hashtag_id)
);

-- Create indexes for better performance
CREATE INDEX idx_post_hashtags_post ON post_hashtags(post_id);
CREATE INDEX idx_post_hashtags_hashtag ON post_hashtags(hashtag_id);
CREATE INDEX idx_hashtags_tag ON hashtags(tag);
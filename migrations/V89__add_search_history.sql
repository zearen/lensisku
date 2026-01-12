CREATE TABLE user_search_history (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(userid) ON DELETE SET NULL,
    search_query TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    search_params JSONB
);

CREATE INDEX idx_search_history_user ON user_search_history(user_id);
CREATE INDEX idx_search_history_created ON user_search_history(created_at);

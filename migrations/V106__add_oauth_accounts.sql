CREATE TABLE oauth_accounts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(userid),
    provider VARCHAR(255) NOT NULL,
    provider_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (provider, provider_id)
);

-- Add a column to the users table to indicate if the user signed up via OAuth
ALTER TABLE users ADD COLUMN oauth_signup BOOLEAN DEFAULT FALSE;
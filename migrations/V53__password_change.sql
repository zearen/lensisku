CREATE TABLE password_change_verifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(userid),
    verification_id TEXT NOT NULL UNIQUE,
    verification_code TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT one_active_verification_per_user UNIQUE (user_id, verification_id)
    DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX idx_password_change_user ON password_change_verifications(user_id) WHERE completed_at IS NULL;
CREATE INDEX idx_password_change_cleanup ON password_change_verifications(expires_at) WHERE completed_at IS NULL;
CREATE TABLE IF NOT EXISTS password_reset_requests (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL,
    session_id TEXT NOT NULL UNIQUE,
    token TEXT NOT NULL,
    token_expiry BIGINT NOT NULL,
    created_at BIGINT NOT NULL,
    used BOOLEAN DEFAULT false,
    used_at BIGINT
);

CREATE INDEX idx_password_reset_email_created ON password_reset_requests(email, created_at);
CREATE INDEX idx_password_reset_session_token ON password_reset_requests(session_id, token);
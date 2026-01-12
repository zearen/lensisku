-- Create the user_sessions table
CREATE TABLE user_sessions (
    id BIGSERIAL PRIMARY KEY,
    session_uuid UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMPTZ NULL,
    ip_address INET,
    user_agent TEXT,
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_user
        FOREIGN KEY(user_id)
        REFERENCES users(userid)
        ON DELETE CASCADE
);

-- Create indexes for user_sessions table
CREATE UNIQUE INDEX idx_user_sessions_session_uuid ON user_sessions(session_uuid);
CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_user_sessions_started_at ON user_sessions(started_at);
CREATE INDEX idx_user_sessions_ended_at ON user_sessions(ended_at);

CREATE INDEX idx_user_sessions_last_active_at ON user_sessions(last_active_at);

-- Create the user_session_events table
CREATE TABLE user_session_events (
    id BIGSERIAL PRIMARY KEY,
    session_id BIGINT NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    event_timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    event_details JSONB,
    CONSTRAINT fk_session
        FOREIGN KEY(session_id)
        REFERENCES user_sessions(id)
        ON DELETE CASCADE
);

-- Create indexes for user_session_events table
CREATE INDEX idx_user_session_events_session_id ON user_session_events(session_id);
CREATE INDEX idx_user_session_events_event_type ON user_session_events(event_type);
CREATE INDEX idx_user_session_events_event_timestamp ON user_session_events(event_timestamp);
-- Insert the new permission for viewing user sessions
INSERT INTO permissions (name, description) VALUES
('view_user_sessions_admin', 'Can view user session history for any user')
ON CONFLICT (name) DO NOTHING;

-- Assign the new permission to the 'admin' role
-- This assumes the 'admin' role and the 'view_user_sessions_admin' permission exist.
-- The sync_admin_permissions trigger should ideally handle this,
-- but an explicit insert ensures it if the trigger isn't fired by this script alone.
DO $$
DECLARE
    admin_role TEXT := 'admin';
    session_perm_id INTEGER;
BEGIN
    SELECT id INTO session_perm_id FROM permissions WHERE name = 'view_user_sessions_admin';

    IF session_perm_id IS NOT NULL THEN
        INSERT INTO role_permissions (role, permission_id)
        VALUES (admin_role, session_perm_id)
        ON CONFLICT (role, permission_id) DO NOTHING;
    ELSE
        RAISE WARNING 'Permission view_user_sessions_admin not found, cannot assign to admin role.';
    END IF;
END $$;

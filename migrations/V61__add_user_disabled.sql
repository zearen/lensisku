ALTER TABLE users 
ADD COLUMN disabled BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN disabled_at TIMESTAMP,
ADD COLUMN disabled_by INTEGER REFERENCES users(userid);

-- Add disable user permission
INSERT INTO permissions (name, description) 
VALUES ('disable_user', 'Can disable other users');

-- Grant disable permission to admin and moderator roles
INSERT INTO role_permissions (role, permission_id)
SELECT 'admin'::user_role, id FROM permissions WHERE name = 'disable_user'
UNION ALL
SELECT 'moderator'::user_role, id FROM permissions WHERE name = 'disable_user';

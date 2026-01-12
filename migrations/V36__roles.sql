-- Create roles table
CREATE TYPE user_role AS ENUM ('admin', 'moderator', 'editor', 'user', 'unconfirmed');

-- Create permissions table
CREATE TABLE permissions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

-- Create role_permissions mapping table
CREATE TABLE role_permissions (
    role user_role NOT NULL,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role, permission_id)
);

-- Add role column to users
ALTER TABLE users 
ADD COLUMN role user_role NOT NULL DEFAULT 'unconfirmed',
ADD COLUMN email_confirmed BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN email_confirmation_token TEXT,
ADD COLUMN email_confirmation_sent_at TIMESTAMP;

-- Insert base permissions
INSERT INTO permissions (name, description) VALUES
('create_definition', 'Can create new definitions'),
('edit_definition', 'Can edit definitions'),
('delete_definition', 'Can delete definitions'),
('vote_definition', 'Can vote on definitions'),
('create_comment', 'Can create comments'),
('edit_comment', 'Can edit own comments'),
('delete_comment', 'Can delete own comments'),
('moderate_comments', 'Can moderate all comments'),
('manage_users', 'Can manage user accounts'),
('manage_roles', 'Can assign roles to users');

-- Assign default permissions to roles
INSERT INTO role_permissions (role, permission_id)
SELECT 'admin', id FROM permissions;

INSERT INTO role_permissions (role, permission_id)
SELECT 'moderator', id FROM permissions 
WHERE name IN ('create_definition', 'edit_definition', 'vote_definition', 
              'create_comment', 'edit_comment', 'delete_comment', 'moderate_comments');

INSERT INTO role_permissions (role, permission_id)
SELECT 'editor', id FROM permissions 
WHERE name IN ('create_definition', 'edit_definition', 'vote_definition',
              'create_comment', 'edit_comment', 'delete_comment');

INSERT INTO role_permissions (role, permission_id)
SELECT 'user', id FROM permissions 
WHERE name IN ('create_definition', 'vote_definition', 'create_comment', 
              'edit_comment', 'delete_comment');

-- Create indexes
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_email_token ON users(email_confirmation_token) WHERE email_confirmation_token IS NOT NULL;
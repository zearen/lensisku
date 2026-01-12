 -- Add blocked role to user_role enum
 ALTER TYPE user_role ADD VALUE 'blocked';

 -- Add new permission for managing blocked status
 INSERT INTO permissions (name, description) VALUES
 ('block_user', 'Can block/unblock users');

 -- Assign block_user permission to admin and moderator roles
 INSERT INTO role_permissions (role, permission_id)
 SELECT 'admin', id FROM permissions WHERE name = 'block_user';

 INSERT INTO role_permissions (role, permission_id)
 SELECT 'moderator', id FROM permissions WHERE name = 'block_user';
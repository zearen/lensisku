-- Disable admin role protection trigger
ALTER TABLE role_permissions DISABLE TRIGGER prevent_admin_role_deletion_trigger;

-- Remove disable_user permission from roles
DELETE FROM role_permissions
WHERE permission_id IN (SELECT id FROM permissions WHERE name = 'disable_user');

-- Remove disable_user permission
DELETE FROM permissions WHERE name = 'disable_user';

-- Re-enable admin role protection trigger
ALTER TABLE role_permissions ENABLE TRIGGER prevent_admin_role_deletion_trigger;

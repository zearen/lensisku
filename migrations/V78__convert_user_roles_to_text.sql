-- Drop the enum type and convert role columns to text
BEGIN;

-- Drop triggers and functions that depend on the user_role type
DROP TRIGGER IF EXISTS prevent_admin_role_deletion_trigger ON role_permissions;
DROP TRIGGER IF EXISTS trg_sync_admin_after_permission_changes ON permissions;
DROP TRIGGER IF EXISTS trg_sync_admin_after_role_perms_changes ON role_permissions;
DROP FUNCTION IF EXISTS prevent_admin_role_deletion();
DROP FUNCTION IF EXISTS sync_admin_permissions();

-- Convert role column in users table to text
ALTER TABLE users 
ALTER COLUMN role TYPE text USING role::text;

-- Convert role column in role_permissions table to text
ALTER TABLE role_permissions
ALTER COLUMN role TYPE text USING role::text;

-- Drop the user_role enum type with CASCADE to handle dependencies
DROP TYPE IF EXISTS user_role CASCADE;

-- Recreate triggers and functions with text roles
CREATE OR REPLACE FUNCTION prevent_admin_role_deletion()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.role = 'admin' THEN
        RAISE EXCEPTION 'Cannot delete admin role';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER prevent_admin_role_deletion_trigger
BEFORE DELETE ON role_permissions
FOR EACH ROW EXECUTE FUNCTION prevent_admin_role_deletion();

CREATE OR REPLACE FUNCTION sync_admin_permissions()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO role_permissions (role, permission_id)
    SELECT 'admin', id
    FROM permissions
    WHERE NOT EXISTS (
        SELECT 1 
        FROM role_permissions rp 
        WHERE rp.role = 'admin' 
        AND rp.permission_id = permissions.id
    );
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_sync_admin_after_permission_changes
AFTER INSERT OR DELETE OR UPDATE ON permissions
FOR EACH STATEMENT EXECUTE FUNCTION sync_admin_permissions();

CREATE OR REPLACE TRIGGER trg_sync_admin_after_role_perms_changes
AFTER DELETE OR UPDATE ON role_permissions
FOR EACH ROW
WHEN (OLD.role = 'admin')
EXECUTE FUNCTION sync_admin_permissions();

COMMIT;

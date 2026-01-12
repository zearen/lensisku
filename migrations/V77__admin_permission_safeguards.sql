-- Insert base permissions
INSERT INTO permissions (name, description) VALUES
('bulk_import', 'Can mass import definitions'),
('revert_entry_version', 'Can revert changes to a dictionary entry') on conflict do nothing
;

-- Prevent admin role deletion
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

-- Create function to sync admin permissions
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

-- Create triggers for permission table changes
CREATE OR REPLACE TRIGGER trg_sync_admin_after_permission_changes
AFTER INSERT OR DELETE OR UPDATE ON permissions
FOR EACH STATEMENT EXECUTE FUNCTION sync_admin_permissions();

-- Create triggers for role_permission changes affecting admin
CREATE OR REPLACE TRIGGER trg_sync_admin_after_role_perms_changes
AFTER DELETE OR UPDATE ON role_permissions
FOR EACH ROW
WHEN (OLD.role = 'admin')
EXECUTE FUNCTION sync_admin_permissions();


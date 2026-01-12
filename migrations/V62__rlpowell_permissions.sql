-- Set rlpowell as admin
UPDATE users 
SET role = 'admin'
WHERE username = 'rlpowell';

-- Ensure all permissions are granted
INSERT INTO role_permissions (role, permission_id)
SELECT 'admin', id 
FROM permissions 
WHERE NOT EXISTS (
    SELECT 1 
    FROM role_permissions rp 
    WHERE rp.role = 'admin' 
    AND rp.permission_id = permissions.id
);

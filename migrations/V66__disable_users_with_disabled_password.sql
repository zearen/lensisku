-- Update users with password = 'DISABLED' to blocked role
UPDATE users
SET role = 'blocked'
WHERE password = 'DISABLED';

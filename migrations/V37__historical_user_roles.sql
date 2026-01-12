-- Update existing users to have confirmed emails
UPDATE users 
SET 
    email_confirmed = true,
    role = CASE 
        WHEN role = 'unconfirmed' THEN 'user'::user_role
        ELSE role
    END
WHERE 
    -- Only update users that existed before the email confirmation feature
    created_at < CURRENT_TIMESTAMP;

-- Set roles for historical users
UPDATE users
SET role = 'editor'::user_role;

-- Set officialdata user as admin
UPDATE users
SET role = 'admin'::user_role
WHERE username = 'officialdata';

-- Create index for better performance when checking email confirmation status
CREATE INDEX idx_users_email_confirmed ON users(email_confirmed);
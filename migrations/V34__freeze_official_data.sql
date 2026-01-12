-- Get user ID for official_data
WITH official_data_user AS (
    SELECT userid 
    FROM users 
    WHERE username = 'officialdata'
)

-- Update definitions
UPDATE definitions
SET owner_only = true
WHERE userid = (SELECT userid FROM official_data_user);

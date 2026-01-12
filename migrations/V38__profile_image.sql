-- Migration for profile images
CREATE TABLE user_profile_images (
    user_id INTEGER PRIMARY KEY REFERENCES users(userid),
    image_data BYTEA NOT NULL,
    mime_type TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Add function to check if user has profile image
CREATE OR REPLACE FUNCTION has_profile_image(userid INTEGER) 
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM user_profile_images 
        WHERE user_id = userid
    );
END;
$$ LANGUAGE plpgsql;
-- Add definition versions table to track history of definition changes
CREATE TABLE definition_versions (
    version_id SERIAL PRIMARY KEY,
    definition_id INTEGER NOT NULL,
    langid INTEGER NOT NULL,
    valsiid INTEGER NOT NULL,
    definition TEXT NOT NULL,
    notes TEXT,
    selmaho TEXT,
    jargon TEXT,
    gloss_keywords JSONB DEFAULT '[]'::jsonb,
    place_keywords JSONB DEFAULT '[]'::jsonb,
    user_id INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    message TEXT NOT NULL,
    
    FOREIGN KEY (definition_id) REFERENCES definitions(definitionid),
    FOREIGN KEY (langid) REFERENCES languages(langid),
    FOREIGN KEY (valsiid) REFERENCES valsi(valsiid),
    FOREIGN KEY (user_id) REFERENCES users(userid)
);

-- Create indexes for common queries
CREATE INDEX idx_definition_versions_definition_id ON definition_versions(definition_id);
CREATE INDEX idx_definition_versions_created_at ON definition_versions(created_at);

-- Create function to determine if user can edit a definition
CREATE OR REPLACE FUNCTION can_edit_definition(
    p_definition_id INTEGER,
    p_user_id INTEGER
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM definitions d
        WHERE d.definitionid = p_definition_id
        AND (
            d.userid = p_user_id  -- User is the owner
            OR NOT d.owner_only    -- Definition allows edits from others
        )
    );
END;
$$ LANGUAGE plpgsql;

-- Add owner_only column to definitions table
ALTER TABLE definitions ADD COLUMN owner_only BOOLEAN NOT NULL DEFAULT FALSE;

-- Add owner_only to definition_versions table to track history
ALTER TABLE definition_versions ADD COLUMN owner_only BOOLEAN NOT NULL DEFAULT FALSE;

-- Create function to check if user can edit definition
CREATE OR REPLACE FUNCTION can_edit_definition(
    p_definition_id INT,
    p_user_id INT
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM definitions d
        WHERE d.definitionid = p_definition_id
        AND (
            d.userid = p_user_id  -- User is the owner
            OR NOT d.owner_only   -- Definition is not owner-only
        )
    );
END;
$$ LANGUAGE plpgsql;
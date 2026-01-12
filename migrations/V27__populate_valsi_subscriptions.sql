-- Add historical definition-based subscriptions
WITH definition_interactions AS (
    SELECT DISTINCT
        d.valsiid as valsi_id,
        d.userid as user_id,
        'definition'::subscription_trigger as trigger_type,
        d.definitionid as source_definition_id,
        MIN(d.created_at) as first_interaction
    FROM definitions d
    GROUP BY d.valsiid, d.userid, d.definitionid
)
INSERT INTO valsi_subscriptions (
    valsi_id,
    user_id,
    created_at,
    trigger_type,
    source_definition_id
)
SELECT 
    valsi_id,
    user_id,
    first_interaction,
    trigger_type,
    source_definition_id
FROM definition_interactions
ON CONFLICT (valsi_id, user_id, trigger_type) DO NOTHING;

-- Add historical edit-based subscriptions (separate from creations)
WITH edit_interactions AS (
    SELECT DISTINCT
        d.valsiid as valsi_id,
        dv.user_id,
        'edit'::subscription_trigger as trigger_type,
        d.definitionid as source_definition_id,
        MIN(dv.created_at) as first_interaction
    FROM definition_versions dv
    JOIN definitions d ON d.definitionid = dv.definition_id
    WHERE dv.user_id != d.userid  -- Only consider edits by users who didn't create the definition
    GROUP BY d.valsiid, dv.user_id, d.definitionid
)
INSERT INTO valsi_subscriptions (
    valsi_id,
    user_id,
    created_at,
    trigger_type,
    source_definition_id
)
SELECT 
    valsi_id,
    user_id,
    first_interaction,
    trigger_type,
    source_definition_id
FROM edit_interactions
ON CONFLICT (valsi_id, user_id, trigger_type) DO NOTHING;

-- Add historical comment-based subscriptions
WITH comment_interactions AS (
    SELECT DISTINCT
        t.valsiid as valsi_id,
        c.userid as user_id,
        'comment'::subscription_trigger as trigger_type,
        c.commentid as source_comment_id,
        MIN(to_timestamp(c.time)) as first_interaction
    FROM comments c
    JOIN threads t ON c.threadid = t.threadid
    WHERE t.valsiid > 0  -- Ensure it's a valsi-related thread
    GROUP BY t.valsiid, c.userid, c.commentid
)
INSERT INTO valsi_subscriptions (
    valsi_id,
    user_id,
    created_at,
    trigger_type,
    source_comment_id
)
SELECT 
    valsi_id,
    user_id,
    first_interaction,
    trigger_type,
    source_comment_id
FROM comment_interactions
ON CONFLICT (valsi_id, user_id, trigger_type) DO NOTHING;
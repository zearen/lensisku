-- Create enum for subscription trigger types
CREATE TYPE subscription_trigger AS ENUM ('comment', 'definition', 'edit');

-- Create table for valsi subscriptions
CREATE TABLE valsi_subscriptions (
    subscription_id SERIAL PRIMARY KEY,
    valsi_id INTEGER NOT NULL REFERENCES valsi(valsiid),
    user_id INTEGER NOT NULL REFERENCES users(userid),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    unsubscribed BOOLEAN NOT NULL DEFAULT false,
    unsubscribed_at TIMESTAMP,
    trigger_type subscription_trigger NOT NULL,
    -- Track what caused the subscription
    source_definition_id INTEGER REFERENCES definitions(definitionid),
    source_comment_id INTEGER REFERENCES comments(commentid),
    UNIQUE (valsi_id, user_id, trigger_type)
);

-- Create index for faster lookups
CREATE INDEX idx_valsi_subs_valsi_user ON valsi_subscriptions(valsi_id, user_id);
CREATE INDEX idx_valsi_subs_user ON valsi_subscriptions(user_id);

-- Create function to automatically subscribe users when they create content
CREATE OR REPLACE FUNCTION auto_subscribe_on_content() RETURNS TRIGGER AS $$
BEGIN
    -- For new definitions
    IF TG_TABLE_NAME = 'definitions' THEN
        INSERT INTO valsi_subscriptions (valsi_id, user_id, trigger_type, source_definition_id)
        VALUES (NEW.valsiid, NEW.userid, 'definition', NEW.definitionid)
        ON CONFLICT (valsi_id, user_id, trigger_type) DO NOTHING;
    
    -- For new comments
    ELSIF TG_TABLE_NAME = 'comments' THEN
        -- Get the valsi_id from the thread
        INSERT INTO valsi_subscriptions (valsi_id, user_id, trigger_type, source_comment_id)
        SELECT t.valsiid, NEW.userid, 'comment', NEW.commentid
        FROM threads t
        WHERE t.threadid = NEW.threadid
        ON CONFLICT (valsi_id, user_id, trigger_type) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for automatic subscriptions
CREATE TRIGGER definition_subscription_trigger
    AFTER INSERT ON definitions
    FOR EACH ROW
    EXECUTE FUNCTION auto_subscribe_on_content();

CREATE TRIGGER comment_subscription_trigger
    AFTER INSERT ON comments
    FOR EACH ROW
    EXECUTE FUNCTION auto_subscribe_on_content();

-- Function to notify subscribers
CREATE OR REPLACE FUNCTION notify_valsi_subscribers(
    p_valsi_id INTEGER,
    p_event_type TEXT,
    p_message TEXT,
    p_link TEXT,
    p_actor_id INTEGER
) RETURNS void AS $$
DECLARE
    v_user_id INTEGER;
    v_email TEXT;
    v_username TEXT;
BEGIN
    FOR v_user_id, v_email, v_username IN
        SELECT DISTINCT 
            vs.user_id,
            u.email,
            u.username
        FROM valsi_subscriptions vs
        JOIN users u ON vs.user_id = u.userid
        WHERE vs.valsi_id = p_valsi_id
        AND NOT vs.unsubscribed
        AND vs.user_id != p_actor_id  -- Don't notify the actor
        AND u.email IS NOT NULL
    LOOP
        -- Here you would typically queue an email notification
        -- For now, we'll just insert into a notification log table
        INSERT INTO user_notifications (
            user_id,
            notification_type,
            message,
            link,
            valsi_id,
            actor_id,
            created_at
        ) VALUES (
            v_user_id,
            p_event_type,
            p_message,
            p_link,
            p_valsi_id,
            p_actor_id,
            CURRENT_TIMESTAMP
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create notifications table
CREATE TABLE user_notifications (
    notification_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(userid),
    notification_type TEXT NOT NULL,
    message TEXT NOT NULL,
    link TEXT,
    valsi_id INTEGER REFERENCES valsi(valsiid),
    actor_id INTEGER REFERENCES users(userid),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMP
);

CREATE INDEX idx_notifications_user ON user_notifications(user_id, created_at);

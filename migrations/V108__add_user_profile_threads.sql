-- Add target_user_id column to threads table
ALTER TABLE public.threads
ADD COLUMN target_user_id INTEGER REFERENCES public.users(userid) ON DELETE CASCADE DEFAULT NULL;

-- Make existing context columns nullable
ALTER TABLE public.threads
ALTER COLUMN valsiid DROP NOT NULL,
ALTER COLUMN natlangwordid DROP NOT NULL,
ALTER COLUMN definitionid DROP NOT NULL;

-- Add a check constraint to ensure at least one context is provided for a thread
ALTER TABLE public.threads
ADD CONSTRAINT threads_context_check
CHECK (
    valsiid IS NOT NULL OR
    natlangwordid IS NOT NULL OR
    definitionid IS NOT NULL OR
    target_user_id IS NOT NULL
);

-- Add an index for target_user_id
CREATE INDEX idx_threads_target_user_id ON public.threads (target_user_id) WHERE target_user_id IS NOT NULL;

-- Update auto_subscribe_on_content function to handle NULL valsiid in threads
CREATE OR REPLACE FUNCTION public.auto_subscribe_on_content() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_TABLE_NAME = 'definitions' THEN
        INSERT INTO valsi_subscriptions (valsi_id, user_id, trigger_type, source_definition_id)
        VALUES (NEW.valsiid, NEW.userid, 'definition', NEW.definitionid)
        ON CONFLICT (valsi_id, user_id, trigger_type) DO NOTHING;

    ELSIF TG_TABLE_NAME = 'comments' THEN
        INSERT INTO valsi_subscriptions (valsi_id, user_id, trigger_type, source_comment_id)
        SELECT t.valsiid, NEW.userid, 'comment', NEW.commentid
        FROM threads t
        WHERE t.threadid = NEW.threadid AND t.valsiid IS NOT NULL -- Only subscribe if valsiid is present
        ON CONFLICT (valsi_id, user_id, trigger_type) DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$;

-- Note: The `update_thread_stats` trigger function should continue to work as expected.
-- The fields it populates (like creator_user_id, last_comment_*) are derived
-- from comments within the thread or users table, not directly from valsiid/natlangwordid/definitionid
-- on the threads table itself for these specific stats.
-- The `convenientthreads` view will implicitly filter out threads that don't have valsiid AND natlangwordid
-- due to its INNER JOIN conditions. This might be acceptable or require a future change if user profile threads
-- need to appear in that specific view.

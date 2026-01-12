

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;

CREATE TYPE public.flashcard_direction AS ENUM (
    'direct',
    'reverse',
    'both',
    'fillin',
    'fillin_reverse',
    'fillin_both',
    'just_information',
    'quiz_direct',
    'quiz_reverse',
    'quiz_both'
);

CREATE TYPE public.flashcard_status AS ENUM (
    'new',
    'learning',
    'review',
    'graduated'
);

CREATE TYPE public.payment_provider AS ENUM (
    'stripe',
    'paypal',
    'binance',
    'wise'
);

CREATE TYPE public.payment_status AS ENUM (
    'pending',
    'succeeded',
    'failed',
    'faulty'
);

CREATE TYPE public.subscription_trigger AS ENUM (
    'comment',
    'definition',
    'edit'
);

CREATE TYPE public.user_subscription_status AS ENUM (
    'active',
    'inactive',
    'cancelled',
    'past_due',
    'pending_cancellation'
);

CREATE FUNCTION public.auto_subscribe_on_content() RETURNS trigger
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

CREATE FUNCTION public.can_edit_definition(p_definition_id integer, p_user_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;

CREATE FUNCTION public.check_level_completion(p_user_id integer, p_level_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_min_cards INTEGER;
    v_min_success_rate FLOAT;
    v_completion_rate FLOAT;
    v_cards_completed INTEGER;
BEGIN
    SELECT min_cards, min_success_rate
    INTO v_min_cards, v_min_success_rate
    FROM flashcard_levels
    WHERE level_id = p_level_id;

    SELECT
        cards_completed,
        CASE WHEN total_answers > 0
            THEN correct_answers::FLOAT / total_answers::FLOAT
            ELSE 0
        END
    INTO v_cards_completed, v_completion_rate
    FROM user_level_progress
    WHERE user_id = p_user_id AND level_id = p_level_id;

    RETURN v_cards_completed >= v_min_cards
        AND v_completion_rate >= v_min_success_rate;
END;
$$;

CREATE FUNCTION public.check_level_prerequisites(p_user_id integer, p_level_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_prerequisites_met BOOLEAN;
BEGIN
    SELECT COALESCE(bool_and(ulp.completed_at IS NOT NULL), true)
    INTO v_prerequisites_met
    FROM level_prerequisites lp
    JOIN user_level_progress ulp
        ON ulp.level_id = lp.prerequisite_id
        AND ulp.user_id = p_user_id
    WHERE lp.level_id = p_level_id;

    RETURN v_prerequisites_met;
END;
$$;

CREATE FUNCTION public.check_reaction_limit(p_user_id integer, p_comment_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN (
        SELECT COALESCE(reaction_count, 0) < 5
        FROM user_reaction_counts
        WHERE user_id = p_user_id AND comment_id = p_comment_id
        UNION ALL
        SELECT true
        LIMIT 1
    );
END;
$$;

CREATE FUNCTION public.clean_subject(subject text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    clean text;
    modified boolean;
    bracket_start int;
    bracket_end int;
BEGIN
    clean := subject;

    LOOP
        modified := false;
        clean := trim(clean);

        IF lower(substr(clean, 1, 3)) = 're:' THEN
            clean := trim(substr(clean, 4));
            modified := true;
            CONTINUE;
        END IF;

        bracket_start := position('[' in clean);
        IF bracket_start > 0 THEN
            bracket_end := position(']' in substr(clean, bracket_start));
            IF bracket_end > 0 THEN
                clean := trim(substr(clean, 1, bracket_start - 1) ||
                            substr(clean, bracket_start + bracket_end));
                modified := true;
                CONTINUE;
            END IF;
        END IF;

        EXIT WHEN NOT modified;
    END LOOP;

    clean := regexp_replace(clean, '\s+', ' ', 'g');

    RETURN trim(clean);
END;
$$;

CREATE FUNCTION public.cleanup_item_images() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM collection_item_images WHERE item_id = OLD.item_id;
    RETURN OLD;
END;
$$;

CREATE FUNCTION public.cleanup_orphaned_images() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM definition_images WHERE definition_id = OLD.definitionid;
    RETURN OLD;
END;
$$;

CREATE FUNCTION public.create_user_balance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO user_balances (user_id, balance_cents, created_at, updated_at)
    VALUES (NEW.userid, 0, NOW(), NOW())
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE FUNCTION public.delete_orphaned_natlangwords() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM natlangwords n
    WHERE NOT EXISTS (
        SELECT 1 FROM threads t WHERE t.natlangwordid = n.wordid
    )
    AND NOT EXISTS (
        SELECT 1 FROM natlangwordvotes v WHERE v.natlangwordid = n.wordid
    )
    AND NOT EXISTS (
        SELECT 1 FROM keywordmapping k WHERE k.natlangwordid = n.wordid
    );
END;
$$;

CREATE FUNCTION public.extract_plain_content() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
 DECLARE
     element JSONB;
     result TEXT := '';
 BEGIN
     IF NEW.content IS NULL THEN
         NEW.plain_content := '';
         RETURN NEW;
     END IF;

     FOR element IN SELECT * FROM jsonb_array_elements(NEW.content)
    LOOP
        IF element->>'type' = 'text' THEN
            result := result || (element->>'data') || ' ';
        END IF;
     END LOOP;

     NEW.plain_content := TRIM(result);
     RETURN NEW;
END;
$$;

CREATE FUNCTION public.has_profile_image(userid integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM user_profile_images
        WHERE user_id = userid
    );
END;
$$;

CREATE FUNCTION public.notify_valsi_subscribers(p_valsi_id integer, p_event_type text, p_message text, p_link text, p_actor_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;

CREATE FUNCTION public.parse_email_date(date_text text) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $_$
DECLARE
  cleaned_date text;
BEGIN
  IF date_text IS NULL OR date_text = '' THEN
      RETURN NULL;
  END IF;

  cleaned_date := regexp_replace(date_text, '\s*\([A-Z]+\)', '', 'g');

  cleaned_date := regexp_replace(cleaned_date, '\sEST\s*$', ' -0500', 'g');
  cleaned_date := regexp_replace(cleaned_date, '\sEDT\s*$', ' -0400', 'g');

  RETURN cleaned_date::timestamptz;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$_$;

CREATE FUNCTION public.prevent_admin_role_deletion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.role = 'admin' THEN
        RAISE EXCEPTION 'Cannot delete admin role';
    END IF;
    RETURN OLD;
END;
$$;

CREATE FUNCTION public.process_successful_payment(p_payment_id integer, p_amount_cents bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(p_payment_id);

    WITH payment_info AS (
        UPDATE payments
        SET status = 'succeeded',
            completed_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_payment_id
        AND status = 'pending'
        RETURNING user_id
    )
    INSERT INTO balance_transactions (
        user_id,
        amount_cents,
        currency,
        transaction_type,
        reference_id
    )
    SELECT
        user_id,
        p_amount_cents,
        'USD',
        'payment_credit',
        p_payment_id::TEXT
    FROM payment_info;

    UPDATE user_balances
    SET balance_cents = balance_cents + p_amount_cents,
        total_spent_cents = total_spent_cents + p_amount_cents,
        updated_at = CURRENT_TIMESTAMP
    FROM payments
    WHERE payments.id = p_payment_id
    AND user_balances.user_id = payments.user_id;
END;
$$;

CREATE FUNCTION public.refresh_natlangwordbestplaces_for_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    PERFORM reset_natlangwordbestplace(OLD.natlangwordid);
    RETURN NULL;
  END;
$$;

CREATE FUNCTION public.refresh_natlangwordbestplaces_for_upsert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    PERFORM reset_natlangwordbestplace(NEW.natlangwordid);
    RETURN NULL;
  END;
$$;

CREATE FUNCTION public.refresh_reaction_counts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY user_reaction_counts;
    RETURN NULL;
END;
$$;

CREATE FUNCTION public.refresh_valsibestdefinitions_for_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    PERFORM reset_valsibestdefinition(OLD.valsiid, OLD.langid);
    RETURN NULL;
  END;
$$;

CREATE FUNCTION public.refresh_valsibestdefinitions_for_upsert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    PERFORM reset_valsibestdefinition(NEW.valsiid, NEW.langid);
    RETURN NULL;
  END;
$$;

CREATE FUNCTION public.reload_natlangwordbestplaces() RETURNS void
    LANGUAGE plpgsql
    AS $$
  DECLARE
    _wordid integer;
  BEGIN

    TRUNCATE natlangwordbestplaces;

    FOR _wordid IN
      SELECT DISTINCT natlangwordid AS wordid
        FROM natlangwordvotes
    LOOP
      PERFORM reset_natlangwordbestplace(_wordid);
    END LOOP;

  END;
$$;

CREATE FUNCTION public.reload_valsibestdefinitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
  DECLARE
    _row RECORD;
  BEGIN

    TRUNCATE valsibestdefinitions;

    FOR _row IN
      SELECT DISTINCT valsiid, langid
        FROM definitionvotes
    LOOP
      PERFORM reset_valsibestdefinition(_row.valsiid, _row.langid);
    END LOOP;

  END;
$$;

CREATE FUNCTION public.reset_natlangwordbestplace(_wordid integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  DECLARE
    _new RECORD;
  BEGIN

    SELECT natlangwordid AS wordid, definitionid, place, min(time) AS time, sum(value) AS score
      INTO _new
      FROM natlangwordvotes
      WHERE natlangwordid = _wordid
      GROUP BY wordid, definitionid, place
      ORDER BY score DESC, time
      LIMIT 1;

    DELETE
      FROM natlangwordbestplaces
      WHERE wordid = _wordid;

    IF _new IS NOT NULL THEN
      INSERT
        INTO natlangwordbestplaces (wordid, definitionid, place, score)
        VALUES (_new.wordid, _new.definitionid, _new.place, _new.score);
    END IF;

  END;
$$;

CREATE FUNCTION public.reset_valsibestdefinition(_valsiid integer, _langid integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  DECLARE
    _new RECORD;
  BEGIN

    SELECT valsiid, langid, definitionid, min(time) as time, sum(value) AS score
      INTO _new
      FROM definitionvotes
      WHERE valsiid = _valsiid AND langid = _langid
      GROUP BY valsiid, langid, definitionid
      ORDER BY score DESC, time
      LIMIT 1;

    DELETE
      FROM valsibestdefinitions
      WHERE valsiid = _valsiid AND langid = _langid;

    IF _new IS NOT NULL THEN
      INSERT
        INTO valsibestdefinitions (valsiid, langid, definitionid, score)
        VALUES (_new.valsiid, _new.langid, _new.definitionid, _new.score);
    END IF;

  END;
$$;

CREATE FUNCTION public.set_message_sent_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.date IS NOT NULL AND NEW.sent_at IS NULL THEN
      NEW.sent_at := parse_email_date(NEW.date);
  END IF;
  IF NEW.sent_at IS NULL THEN
      NEW.sent_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.sync_admin_permissions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;

CREATE FUNCTION public.trigger_cleanup_natlangwords() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM public.delete_orphaned_natlangwords();
    PERFORM public.reload_natlangwordbestplaces();
    RETURN NULL;
END;
$$;

CREATE FUNCTION public.trigger_set_collection_item_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.trigger_set_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.update_cleaned_subject() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.cleaned_subject := clean_subject(NEW.subject);
    RETURN NEW;
END;
$$;

CREATE FUNCTION public.update_comment_activity_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.last_activity_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE FUNCTION public.update_comment_counter(p_comment_id integer, p_counter_type text, p_increment boolean) RETURNS void
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_amount INTEGER;
BEGIN
    v_amount := CASE WHEN p_increment THEN 1 ELSE -1 END;

    EXECUTE format('
        INSERT INTO comment_activity_counters (comment_id, total_%I)
        VALUES ($1, $2)
        ON CONFLICT (comment_id)
        DO UPDATE SET total_%I = comment_activity_counters.total_%I + $2',
        p_counter_type, p_counter_type, p_counter_type
    ) USING p_comment_id, v_amount;
END;
$_$;

CREATE FUNCTION public.update_comment_counter_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE FUNCTION public.update_comment_reply_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.parentid IS NOT NULL THEN
            UPDATE comment_activity_counters
            SET total_replies = total_replies + 1
            WHERE comment_id = NEW.parentid;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.parentid IS NOT NULL THEN
            UPDATE comment_activity_counters
            SET total_replies = total_replies - 1
            WHERE comment_id = OLD.parentid;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

CREATE FUNCTION public.update_followers_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET followers = followers + 1
        WHERE userid = NEW.followee_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users SET followers = followers - 1
        WHERE userid = OLD.followee_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE FUNCTION public.update_level_progress() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO user_level_progress AS ulp (
        user_id, level_id,
        cards_completed, correct_answers, total_answers,
        last_activity_at
    )
    SELECT
        NEW.user_id,
        fli.level_id,
        COUNT(DISTINCT fr.flashcard_id),
        SUM(CASE WHEN fr.rating >= 3 THEN 1 ELSE 0 END),
        COUNT(*),
        CURRENT_TIMESTAMP
    FROM flashcard_review_history fr
    JOIN flashcard_level_items fli ON fr.flashcard_id = fli.flashcard_id
    WHERE fr.user_id = NEW.user_id
    AND fli.level_id = (
        SELECT level_id
        FROM flashcard_level_items
        WHERE flashcard_id = NEW.flashcard_id
    )
    GROUP BY fli.level_id
    ON CONFLICT (user_id, level_id) DO UPDATE
    SET
        cards_completed = EXCLUDED.cards_completed,
        correct_answers = EXCLUDED.correct_answers,
        total_answers = EXCLUDED.total_answers,
        last_activity_at = EXCLUDED.last_activity_at,
        completed_at = CASE
            WHEN check_level_completion(EXCLUDED.user_id, EXCLUDED.level_id)
                AND ulp.completed_at IS NULL
            THEN CURRENT_TIMESTAMP
            ELSE ulp.completed_at
        END;

    UPDATE user_level_progress
    SET unlocked_at = CASE
        WHEN check_level_prerequisites(user_id, level_id)
            AND unlocked_at IS NULL
        THEN CURRENT_TIMESTAMP
        ELSE unlocked_at
    END
    WHERE user_id = NEW.user_id;

    RETURN NEW;
END;
$$;

CREATE FUNCTION public.update_premium_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.balance_cents > OLD.balance_cents THEN
        NEW.premium_expires_at = GREATEST(
            COALESCE(NEW.premium_expires_at, NOW()),
            NOW() + INTERVAL '1 month'
        );
    END IF;

    IF NEW.premium_expires_at IS NOT NULL AND NEW.premium_expires_at < NOW() THEN
        NEW.balance_cents = 0;
        NEW.premium_expires_at = NULL;
    END IF;

    RETURN NEW;
END;
$$;

CREATE FUNCTION public.update_reaction_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM comment_reactions
            WHERE comment_id = NEW.comment_id
            AND user_id = NEW.user_id
            AND id != NEW.id
        ) THEN
            UPDATE comment_activity_counters
            SET total_reactions = total_reactions + 1,
                last_activity_at = CURRENT_TIMESTAMP
            WHERE comment_id = NEW.comment_id;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM comment_reactions
            WHERE comment_id = OLD.comment_id
            AND user_id = OLD.user_id
        ) THEN
            UPDATE comment_activity_counters
            SET total_reactions = total_reactions - 1,
                last_activity_at = CURRENT_TIMESTAMP
            WHERE comment_id = OLD.comment_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

CREATE FUNCTION public.update_thread_stats() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        UPDATE threads SET
            last_comment_id = (SELECT commentid FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_user_id = (SELECT userid FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_time = (SELECT time FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_subject = (SELECT subject FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_content = (SELECT content FROM comments WHERE threadid = OLD.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            total_comments = (SELECT COUNT(*) FROM comments WHERE threadid = OLD.threadid),
            first_comment_subject = (SELECT subject FROM comments WHERE threadid = OLD.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            first_comment_content = (SELECT content FROM comments WHERE threadid = OLD.threadid ORDER BY time ASC, commentid ASC LIMIT 1)
        WHERE threadid = OLD.threadid;
    END IF;

    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        UPDATE threads SET
            last_comment_id = (SELECT commentid FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_user_id = (SELECT userid FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_time = (SELECT time FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_subject = (SELECT subject FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            last_comment_content = (SELECT content FROM comments WHERE threadid = NEW.threadid ORDER BY time DESC, commentid DESC LIMIT 1),
            total_comments = (SELECT COUNT(*) FROM comments WHERE threadid = NEW.threadid),
            first_comment_subject = (SELECT subject FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            first_comment_content = (SELECT content FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            creator_user_id = (SELECT userid FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1),
            creator_username = (SELECT username FROM users WHERE userid = (SELECT userid FROM comments WHERE threadid = NEW.threadid ORDER BY time ASC, commentid ASC LIMIT 1))
        WHERE threadid = NEW.threadid;
    END IF;

    RETURN NULL;
END;
$$;

SET default_tablespace = '';

SET default_table_access_method = heap;

CREATE TABLE public.balance_transactions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    amount_cents bigint NOT NULL,
    currency text NOT NULL,
    transaction_type text NOT NULL,
    reference_id text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.balance_transactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.balance_transactions_id_seq OWNED BY public.balance_transactions.id;

CREATE TABLE public.cached_dictionary_exports (
    id integer NOT NULL,
    language_tag text NOT NULL,
    format text NOT NULL,
    content bytea NOT NULL,
    content_type text NOT NULL,
    filename text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.cached_dictionary_exports_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.cached_dictionary_exports_id_seq OWNED BY public.cached_dictionary_exports.id;

CREATE TABLE public.collection_item_images (
    id integer NOT NULL,
    item_id integer NOT NULL,
    image_data bytea NOT NULL,
    mime_type text NOT NULL,
    side text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT collection_item_images_side_check CHECK ((side = ANY (ARRAY['front'::text, 'back'::text])))
);

CREATE SEQUENCE public.collection_item_images_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.collection_item_images_id_seq OWNED BY public.collection_item_images.id;

CREATE TABLE public.collection_items (
    item_id integer NOT NULL,
    collection_id integer NOT NULL,
    definition_id integer,
    notes text,
    added_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    free_content_front text,
    free_content_back text,
    auto_progress boolean DEFAULT true NOT NULL,
    langid integer,
    owner_user_id integer,
    license character varying(50),
    script character varying(4),
    is_original boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_content_check CHECK ((((definition_id IS NOT NULL) AND (free_content_front IS NULL) AND (free_content_back IS NULL)) OR ((definition_id IS NULL) AND (free_content_front IS NOT NULL) AND (free_content_back IS NOT NULL))))
);

CREATE SEQUENCE public.collection_items_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.collection_items_item_id_seq OWNED BY public.collection_items.item_id;

CREATE TABLE public.collections (
    collection_id integer NOT NULL,
    user_id integer NOT NULL,
    name text NOT NULL,
    description text,
    is_public boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.collections_collection_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.collections_collection_id_seq OWNED BY public.collections.collection_id;

CREATE TABLE public.comment_activity_counters (
    comment_id integer NOT NULL,
    total_likes bigint DEFAULT 0 NOT NULL,
    total_bookmarks bigint DEFAULT 0 NOT NULL,
    total_replies bigint DEFAULT 0 NOT NULL,
    total_opinions bigint DEFAULT 0 NOT NULL,
    last_activity_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    total_reactions bigint DEFAULT 0 NOT NULL
);

CREATE TABLE public.comment_bookmarks (
    comment_id integer NOT NULL,
    user_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE public.comment_counters (
    comment_id integer NOT NULL,
    total_reactions bigint DEFAULT 0 NOT NULL,
    total_replies bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE public.comment_likes (
    comment_id integer NOT NULL,
    user_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE public.comment_media (
    media_id integer NOT NULL,
    comment_id integer,
    media_type text NOT NULL,
    media_data bytea,
    text_content text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_media_check CHECK ((((media_type = 'image'::text) AND (media_data IS NOT NULL)) OR ((media_type = 'text'::text) AND (text_content IS NOT NULL)) OR ((media_type = 'header'::text) AND (text_content IS NOT NULL))))
);

CREATE SEQUENCE public.comment_media_media_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.comment_media_media_id_seq OWNED BY public.comment_media.media_id;

CREATE TABLE public.comment_opinion_votes (
    opinion_id bigint NOT NULL,
    user_id integer NOT NULL,
    comment_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE public.comment_opinions (
    id bigint NOT NULL,
    comment_id integer NOT NULL,
    user_id integer NOT NULL,
    opinion character varying(12) NOT NULL,
    votes integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.comment_opinions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.comment_opinions_id_seq OWNED BY public.comment_opinions.id;

CREATE TABLE public.comment_reactions (
    id integer NOT NULL,
    comment_id integer NOT NULL,
    user_id integer NOT NULL,
    reaction character varying(32) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.comment_reactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.comment_reactions_id_seq OWNED BY public.comment_reactions.id;

CREATE TABLE public.comments (
    commentid integer NOT NULL,
    threadid integer NOT NULL,
    parentid integer,
    userid integer NOT NULL,
    commentnum integer NOT NULL,
    "time" integer NOT NULL,
    subject text,
    content jsonb,
    plain_content text
);

CREATE SEQUENCE public.comments_commentid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.comments_commentid_seq OWNED BY public.comments.commentid;

CREATE TABLE public.threads (
    threadid integer NOT NULL,
    valsiid integer,
    natlangwordid integer,
    definitionid integer,
    last_comment_id integer,
    last_comment_user_id integer,
    last_comment_time integer,
    last_comment_subject text,
    last_comment_content jsonb,
    total_comments integer DEFAULT 0,
    creator_user_id integer,
    creator_username character varying(64),
    first_comment_subject text,
    first_comment_content jsonb,
    target_user_id integer,
    CONSTRAINT threads_context_check CHECK (((valsiid IS NOT NULL) OR (natlangwordid IS NOT NULL) OR (definitionid IS NOT NULL) OR (target_user_id IS NOT NULL)))
);

CREATE TABLE public.users (
    userid integer NOT NULL,
    username character varying(64) NOT NULL,
    password text NOT NULL,
    email text NOT NULL,
    realname text,
    url text,
    personal text,
    votesize real DEFAULT 0.0,
    created_at timestamp with time zone NOT NULL,
    followers integer DEFAULT 0 NOT NULL,
    role text NOT NULL,
    email_confirmed boolean DEFAULT false NOT NULL,
    email_confirmation_token text,
    email_confirmation_sent_at timestamp with time zone,
    disabled boolean DEFAULT false NOT NULL,
    disabled_at timestamp with time zone,
    disabled_by integer,
    subscription_status public.user_subscription_status DEFAULT 'inactive'::public.user_subscription_status NOT NULL,
    paypal_customer_id text,
    oauth_signup boolean DEFAULT false
);

CREATE VIEW public.convenientcomments AS
 SELECT c.commentid,
    c.threadid,
    c.parentid,
    c.userid,
    u.username,
    u.realname,
    c."time",
    c.subject,
    c.content,
    c.commentnum,
    cc.total_reactions,
    cc.total_replies,
    t.valsiid,
    t.definitionid
   FROM (((public.comments c
     JOIN public.users u ON ((c.userid = u.userid)))
     JOIN public.threads t ON ((c.threadid = t.threadid)))
     LEFT JOIN public.comment_counters cc ON ((c.commentid = cc.comment_id)));

CREATE TABLE public.definitions (
    langid integer NOT NULL,
    valsiid integer NOT NULL,
    definitionnum integer NOT NULL,
    definitionid integer NOT NULL,
    definition text NOT NULL,
    notes text,
    userid integer NOT NULL,
    "time" integer NOT NULL,
    selmaho text,
    jargon text,
    owner_only boolean DEFAULT false NOT NULL,
    etymology text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    embedding public.vector(384),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE public.languages (
    langid integer NOT NULL,
    tag character varying(128) NOT NULL,
    englishname text NOT NULL,
    lojbanname text NOT NULL,
    realname text NOT NULL,
    forlojban text,
    url text
);

CREATE TABLE public.valsi (
    valsiid integer NOT NULL,
    word text NOT NULL,
    typeid smallint NOT NULL,
    userid integer NOT NULL,
    "time" integer NOT NULL,
    rafsi text,
    source_langid integer DEFAULT 1 NOT NULL
);

CREATE VIEW public.convenientdefinitions AS
 SELECT nd.definitionid,
    l.realname AS langrealname,
    l.tag,
    l.langid,
    v.valsiid,
    v.word,
    nd.definition,
    nd.notes,
    u.username,
    u.userid,
    nd."time",
    nd.definitionnum,
    v.rafsi,
    nd.selmaho,
    nd.jargon
   FROM public.definitions nd,
    public.languages l,
    public.valsi v,
    public.users u
  WHERE ((nd.langid = l.langid) AND (nd.valsiid = v.valsiid) AND (nd.userid = u.userid));

CREATE TABLE public.etymology (
    etymologyid integer NOT NULL,
    valsiid integer NOT NULL,
    langid integer NOT NULL,
    content text,
    "time" integer NOT NULL,
    userid integer NOT NULL
);

CREATE VIEW public.convenientetymology AS
 SELECT e.etymologyid,
    v.word,
    e.valsiid,
    l.tag,
    l.realname,
    l.langid,
    e.content,
    e."time",
    u.username,
    u.userid
   FROM public.etymology e,
    public.valsi v,
    public.languages l,
    public.users u
  WHERE ((e.userid = u.userid) AND (e.langid = l.langid) AND (e.valsiid = v.valsiid));

CREATE TABLE public.example (
    exampleid integer NOT NULL,
    valsiid integer NOT NULL,
    definitionid integer NOT NULL,
    examplenum integer NOT NULL,
    content text,
    "time" integer NOT NULL,
    userid integer NOT NULL
);

CREATE VIEW public.convenientexamples AS
 SELECT e.exampleid,
    v.word,
    e.valsiid,
    e.content,
    e."time",
    u.username,
    u.userid,
    e.examplenum,
    e.definitionid
   FROM public.valsi v,
    public.example e,
    public.users u
  WHERE ((v.valsiid = e.valsiid) AND (u.userid = e.userid));

CREATE TABLE public.natlangwords (
    wordid integer NOT NULL,
    langid integer NOT NULL,
    word text NOT NULL,
    meaning text,
    meaningnum integer NOT NULL,
    userid integer NOT NULL,
    "time" integer NOT NULL,
    notes text,
    CONSTRAINT natlangwords_meaning_nonempty CHECK ((length(meaning) > 0))
);

CREATE VIEW public.convenientthreads AS
 SELECT t.threadid,
    t.valsiid,
    v.word AS valsi,
    t.natlangwordid,
    nlw.word AS natlangword,
    l.tag,
    t.definitionid
   FROM public.threads t,
    public.valsi v,
    public.natlangwords nlw,
    public.languages l
  WHERE ((t.valsiid = v.valsiid) AND (t.natlangwordid = nlw.wordid) AND (nlw.langid = l.langid));

CREATE TABLE public.valsitypes (
    typeid smallint NOT NULL,
    descriptor character varying(128)
);

CREATE VIEW public.convenientvalsi AS
 SELECT v.valsiid,
    v.word,
    t.descriptor AS type,
    v.typeid,
    u.username,
    v.userid,
    v."time",
    v.rafsi
   FROM public.valsi v,
    public.valsitypes t,
    public.users u
  WHERE ((v.typeid = t.typeid) AND (v.userid = u.userid));

CREATE TABLE public.definition_images (
    id integer NOT NULL,
    definition_id integer NOT NULL,
    image_data bytea NOT NULL,
    mime_type character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    description text,
    display_order integer DEFAULT 0 NOT NULL,
    created_by integer NOT NULL
);

CREATE SEQUENCE public.definition_images_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.definition_images_id_seq OWNED BY public.definition_images.id;

CREATE TABLE public.definition_versions (
    version_id integer NOT NULL,
    definition_id integer NOT NULL,
    langid integer NOT NULL,
    valsiid integer NOT NULL,
    definition text NOT NULL,
    notes text,
    selmaho text,
    jargon text,
    gloss_keywords jsonb DEFAULT '[]'::jsonb,
    place_keywords jsonb DEFAULT '[]'::jsonb,
    user_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    message text NOT NULL,
    owner_only boolean DEFAULT false NOT NULL,
    etymology text
);

CREATE SEQUENCE public.definition_versions_version_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.definition_versions_version_id_seq OWNED BY public.definition_versions.version_id;

CREATE SEQUENCE public.definitions_definitionid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.definitions_definitionid_seq OWNED BY public.definitions.definitionid;

CREATE TABLE public.definitionvotes (
    valsiid integer NOT NULL,
    langid integer NOT NULL,
    definitionid integer NOT NULL,
    value real NOT NULL,
    userid integer NOT NULL,
    "time" integer NOT NULL
);

CREATE TABLE public.dictionary (
    id integer NOT NULL,
    w text NOT NULL,
    d text,
    n text,
    t text,
    s text,
    g text,
    q text,
    v text,
    r text,
    b text
);

CREATE SEQUENCE public.dictionary_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.dictionary_id_seq OWNED BY public.dictionary.id;

CREATE TABLE public.etymology_backup (
    etymologyid integer,
    valsiid integer,
    langid integer,
    content text,
    "time" integer,
    userid integer
);

CREATE SEQUENCE public.etymology_etymologyid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.etymology_etymologyid_seq OWNED BY public.etymology.etymologyid;

CREATE SEQUENCE public.example_exampleid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.example_exampleid_seq OWNED BY public.example.exampleid;

CREATE TABLE public.flashcards (
    id integer NOT NULL,
    collection_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    item_id integer NOT NULL,
    direction public.flashcard_direction DEFAULT 'direct'::public.flashcard_direction NOT NULL
);

CREATE VIEW public.flashcard_details AS
 SELECT f.id,
    f.collection_id,
    f.created_at,
    f."position",
    f.item_id,
    f.direction,
    ci.notes,
    ci.auto_progress,
    ci.definition_id,
    v.word,
    d.definition,
    d.langid AS definition_language_id
   FROM (((public.flashcards f
     JOIN public.collection_items ci ON ((f.item_id = ci.item_id)))
     LEFT JOIN public.definitions d ON ((ci.definition_id = d.definitionid)))
     LEFT JOIN public.valsi v ON ((d.valsiid = v.valsiid)));

CREATE TABLE public.flashcard_level_items (
    level_id integer NOT NULL,
    flashcard_id integer NOT NULL,
    "position" integer DEFAULT 0 NOT NULL
);

CREATE TABLE public.flashcard_levels (
    level_id integer NOT NULL,
    collection_id integer NOT NULL,
    name text NOT NULL,
    description text,
    min_cards integer DEFAULT 5 NOT NULL,
    min_success_rate double precision DEFAULT 0.8 NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

CREATE SEQUENCE public.flashcard_levels_level_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.flashcard_levels_level_id_seq OWNED BY public.flashcard_levels.level_id;

CREATE TABLE public.flashcard_quiz_options (
    quiz_option_id integer NOT NULL,
    flashcard_id integer NOT NULL,
    correct_answer_text text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.flashcard_quiz_options_quiz_option_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.flashcard_quiz_options_quiz_option_id_seq OWNED BY public.flashcard_quiz_options.quiz_option_id;

CREATE TABLE public.flashcard_review_history (
    id integer NOT NULL,
    user_id integer NOT NULL,
    flashcard_id integer NOT NULL,
    rating integer NOT NULL,
    elapsed_days integer NOT NULL,
    scheduled_days integer NOT NULL,
    state jsonb NOT NULL,
    review_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    card_side text DEFAULT 'direct'::text NOT NULL
);

CREATE SEQUENCE public.flashcard_review_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.flashcard_review_history_id_seq OWNED BY public.flashcard_review_history.id;

CREATE SEQUENCE public.flashcards_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.flashcards_id_seq OWNED BY public.flashcards.id;

CREATE TABLE public.follows (
    follower_id integer NOT NULL,
    followee_id integer NOT NULL,
    follow_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT follows_check CHECK ((follower_id <> followee_id))
);

CREATE TABLE public.hashtags (
    id integer NOT NULL,
    tag character varying(255) NOT NULL
);

CREATE SEQUENCE public.hashtags_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hashtags_id_seq OWNED BY public.hashtags.id;

CREATE TABLE public.keywordmapping (
    natlangwordid integer NOT NULL,
    definitionid integer NOT NULL,
    place integer NOT NULL
);

CREATE SEQUENCE public.languages_langid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.languages_langid_seq OWNED BY public.languages.langid;

CREATE TABLE public.level_prerequisites (
    level_id integer NOT NULL,
    prerequisite_id integer NOT NULL,
    CONSTRAINT level_prerequisites_check CHECK ((level_id <> prerequisite_id))
);

CREATE TABLE public.message_spam_votes (
    message_id integer NOT NULL,
    user_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE public.messages (
    id integer NOT NULL,
    message_id text,
    date text,
    subject text,
    from_address text,
    to_address text,
    content text,
    file_path text,
    cleaned_subject text,
    sent_at timestamp with time zone NOT NULL,
    parts_json jsonb
);

CREATE SEQUENCE public.messages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.messages_id_seq OWNED BY public.messages.id;

CREATE TABLE public.muplis (
    id integer NOT NULL,
    lojban text,
    english text
);

CREATE SEQUENCE public.muplis_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.muplis_id_seq OWNED BY public.muplis.id;

CREATE TABLE public.muplis_update (
    id integer NOT NULL,
    last_update bigint
);

CREATE SEQUENCE public.muplis_update_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.muplis_update_id_seq OWNED BY public.muplis_update.id;

CREATE TABLE public.natlangwordbestplaces (
    wordid integer NOT NULL,
    definitionid integer NOT NULL,
    place integer NOT NULL,
    score integer NOT NULL
);

CREATE VIEW public.natlangwordbestguesses AS
 SELECT wordid AS natlangwordid,
    definitionid,
    place
   FROM public.natlangwordbestplaces
  WHERE (score > 0);

CREATE SEQUENCE public.natlangwords_wordid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.natlangwords_wordid_seq OWNED BY public.natlangwords.wordid;

CREATE TABLE public.natlangwordvotes (
    natlangwordid integer NOT NULL,
    definitionid integer,
    place integer NOT NULL,
    userid integer NOT NULL,
    value integer NOT NULL,
    "time" integer NOT NULL
);

CREATE TABLE public.oauth_accounts (
    id integer NOT NULL,
    user_id integer NOT NULL,
    provider character varying(255) NOT NULL,
    provider_id character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

CREATE SEQUENCE public.oauth_accounts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.oauth_accounts_id_seq OWNED BY public.oauth_accounts.id;

CREATE TABLE public.pages (
    pagename text NOT NULL,
    version integer NOT NULL,
    "time" integer NOT NULL,
    userid integer NOT NULL,
    langid integer NOT NULL,
    content text,
    compressed boolean DEFAULT false,
    latest boolean DEFAULT true
);

CREATE TABLE public.password_change_verifications (
    id integer NOT NULL,
    user_id integer NOT NULL,
    verification_id text NOT NULL,
    verification_code text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.password_change_verifications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.password_change_verifications_id_seq OWNED BY public.password_change_verifications.id;

CREATE TABLE public.password_reset_requests (
    id integer NOT NULL,
    email text NOT NULL,
    session_id text NOT NULL,
    token text NOT NULL,
    token_expiry bigint NOT NULL,
    created_at bigint NOT NULL,
    used boolean DEFAULT false,
    used_at bigint
);

CREATE SEQUENCE public.password_reset_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.password_reset_requests_id_seq OWNED BY public.password_reset_requests.id;

CREATE TABLE public.payment_audit_log (
    id integer NOT NULL,
    payment_id integer NOT NULL,
    user_id integer NOT NULL,
    event_type text NOT NULL,
    details text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.payment_audit_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.payment_audit_log_id_seq OWNED BY public.payment_audit_log.id;

CREATE TABLE public.payments (
    id integer NOT NULL,
    user_id integer NOT NULL,
    provider public.payment_provider NOT NULL,
    provider_payment_id text NOT NULL,
    amount_cents bigint NOT NULL,
    currency text NOT NULL,
    status public.payment_status DEFAULT 'pending'::public.payment_status NOT NULL,
    metadata jsonb,
    idempotency_key text,
    error_message text,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT payments_amount_cents_check CHECK ((amount_cents > 0))
);

CREATE SEQUENCE public.payments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.payments_id_seq OWNED BY public.payments.id;

CREATE TABLE public.paypal_subscriptions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    paypal_plan_id text NOT NULL,
    paypal_subscription_id text NOT NULL,
    status text NOT NULL,
    start_time timestamp with time zone NOT NULL,
    next_billing_time timestamp with time zone,
    last_payment_time timestamp with time zone,
    last_payment_amount_cents bigint,
    last_payment_currency text,
    cancel_reason text,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.paypal_subscriptions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.paypal_subscriptions_id_seq OWNED BY public.paypal_subscriptions.id;

CREATE TABLE public.permissions (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    description text
);

CREATE SEQUENCE public.permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.permissions_id_seq OWNED BY public.permissions.id;

CREATE TABLE public.post_hashtags (
    post_id integer NOT NULL,
    hashtag_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE public.refinery_schema_history (
    version integer NOT NULL,
    name character varying(255),
    applied_on character varying(255),
    checksum character varying(255)
);

CREATE TABLE public.role_permissions (
    role text NOT NULL,
    permission_id integer NOT NULL
);

CREATE SEQUENCE public.threads_threadid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.threads_threadid_seq OWNED BY public.threads.threadid;

CREATE TABLE public.user_balances (
    user_id integer NOT NULL,
    balance_cents bigint DEFAULT 0 NOT NULL,
    total_spent_cents bigint DEFAULT 0 NOT NULL,
    premium_expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT user_balances_balance_cents_check CHECK ((balance_cents >= 0))
);

CREATE TABLE public.user_flashcard_progress (
    id integer NOT NULL,
    user_id integer NOT NULL,
    flashcard_id integer NOT NULL,
    ease_factor double precision DEFAULT 2.5 NOT NULL,
    "interval" integer DEFAULT 0 NOT NULL,
    review_count integer DEFAULT 0 NOT NULL,
    last_reviewed_at timestamp with time zone,
    next_review_at timestamp with time zone,
    status public.flashcard_status DEFAULT 'new'::public.flashcard_status NOT NULL,
    stability double precision DEFAULT 0.0 NOT NULL,
    difficulty double precision DEFAULT 0.0 NOT NULL,
    card_side text DEFAULT 'direct'::text NOT NULL,
    archived boolean DEFAULT false NOT NULL
);

CREATE SEQUENCE public.user_flashcard_progress_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.user_flashcard_progress_id_seq OWNED BY public.user_flashcard_progress.id;

CREATE TABLE public.user_level_progress (
    user_id integer NOT NULL,
    level_id integer NOT NULL,
    cards_completed integer DEFAULT 0 NOT NULL,
    correct_answers integer DEFAULT 0 NOT NULL,
    total_answers integer DEFAULT 0 NOT NULL,
    unlocked_at timestamp with time zone,
    completed_at timestamp with time zone,
    last_activity_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.user_notifications (
    notification_id integer NOT NULL,
    user_id integer NOT NULL,
    notification_type text NOT NULL,
    message text NOT NULL,
    link text,
    valsi_id integer,
    actor_id integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    read_at timestamp with time zone,
    email_sent timestamp with time zone
);

CREATE SEQUENCE public.user_notifications_notification_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.user_notifications_notification_id_seq OWNED BY public.user_notifications.notification_id;

CREATE TABLE public.user_profile_images (
    user_id integer NOT NULL,
    image_data bytea NOT NULL,
    mime_type text NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.user_quiz_answer_history (
    history_id integer NOT NULL,
    user_id integer NOT NULL,
    flashcard_id integer NOT NULL,
    selected_option_text text NOT NULL,
    is_correct_selection boolean NOT NULL,
    presented_options jsonb,
    answered_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.user_quiz_answer_history_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.user_quiz_answer_history_history_id_seq OWNED BY public.user_quiz_answer_history.history_id;

CREATE MATERIALIZED VIEW public.user_reaction_counts AS
 SELECT user_id,
    comment_id,
    count(*) AS reaction_count
   FROM public.comment_reactions
  GROUP BY user_id, comment_id
  WITH NO DATA;

CREATE TABLE public.user_search_history (
    id integer NOT NULL,
    user_id integer,
    search_query text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    search_params jsonb
);

CREATE SEQUENCE public.user_search_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.user_search_history_id_seq OWNED BY public.user_search_history.id;

CREATE TABLE public.user_session_events (
    id bigint NOT NULL,
    session_id bigint NOT NULL,
    event_type character varying(255) NOT NULL,
    event_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_details jsonb
);

CREATE SEQUENCE public.user_session_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.user_session_events_id_seq OWNED BY public.user_session_events.id;

CREATE TABLE public.user_sessions (
    id bigint NOT NULL,
    session_uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id integer NOT NULL,
    started_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ended_at timestamp with time zone,
    ip_address inet,
    user_agent text,
    last_active_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.user_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.user_sessions_id_seq OWNED BY public.user_sessions.id;

CREATE TABLE public.user_settings (
    user_id integer NOT NULL,
    optimal_retention double precision DEFAULT 0.9 NOT NULL,
    last_calculated timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.users_userid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.users_userid_seq OWNED BY public.users.userid;

CREATE TABLE public.users_view (
    userid integer,
    username character varying(64),
    votesize real
);

CREATE TABLE public.valsi_subscriptions (
    subscription_id integer NOT NULL,
    valsi_id integer NOT NULL,
    user_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    unsubscribed boolean DEFAULT false NOT NULL,
    unsubscribed_at timestamp with time zone,
    trigger_type public.subscription_trigger NOT NULL,
    source_definition_id integer,
    source_comment_id integer
);

CREATE SEQUENCE public.valsi_subscriptions_subscription_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.valsi_subscriptions_subscription_id_seq OWNED BY public.valsi_subscriptions.subscription_id;

CREATE SEQUENCE public.valsi_valsiid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.valsi_valsiid_seq OWNED BY public.valsi.valsiid;

CREATE TABLE public.valsibestdefinitions (
    valsiid integer NOT NULL,
    langid integer NOT NULL,
    definitionid integer NOT NULL,
    score integer NOT NULL
);

CREATE VIEW public.valsibestguesses AS
 SELECT valsiid,
    langid,
    definitionid
   FROM public.valsibestdefinitions
  WHERE (score > 0);

CREATE TABLE public.xrefs (
    srctype smallint NOT NULL,
    srcid integer NOT NULL,
    desttype smallint NOT NULL,
    destid integer NOT NULL
);

ALTER TABLE ONLY public.balance_transactions ALTER COLUMN id SET DEFAULT nextval('public.balance_transactions_id_seq'::regclass);

ALTER TABLE ONLY public.cached_dictionary_exports ALTER COLUMN id SET DEFAULT nextval('public.cached_dictionary_exports_id_seq'::regclass);

ALTER TABLE ONLY public.collection_item_images ALTER COLUMN id SET DEFAULT nextval('public.collection_item_images_id_seq'::regclass);

ALTER TABLE ONLY public.collection_items ALTER COLUMN item_id SET DEFAULT nextval('public.collection_items_item_id_seq'::regclass);

ALTER TABLE ONLY public.collections ALTER COLUMN collection_id SET DEFAULT nextval('public.collections_collection_id_seq'::regclass);

ALTER TABLE ONLY public.comment_media ALTER COLUMN media_id SET DEFAULT nextval('public.comment_media_media_id_seq'::regclass);

ALTER TABLE ONLY public.comment_opinions ALTER COLUMN id SET DEFAULT nextval('public.comment_opinions_id_seq'::regclass);

ALTER TABLE ONLY public.comment_reactions ALTER COLUMN id SET DEFAULT nextval('public.comment_reactions_id_seq'::regclass);

ALTER TABLE ONLY public.comments ALTER COLUMN commentid SET DEFAULT nextval('public.comments_commentid_seq'::regclass);

ALTER TABLE ONLY public.definition_images ALTER COLUMN id SET DEFAULT nextval('public.definition_images_id_seq'::regclass);

ALTER TABLE ONLY public.definition_versions ALTER COLUMN version_id SET DEFAULT nextval('public.definition_versions_version_id_seq'::regclass);

ALTER TABLE ONLY public.definitions ALTER COLUMN definitionid SET DEFAULT nextval('public.definitions_definitionid_seq'::regclass);

ALTER TABLE ONLY public.dictionary ALTER COLUMN id SET DEFAULT nextval('public.dictionary_id_seq'::regclass);

ALTER TABLE ONLY public.etymology ALTER COLUMN etymologyid SET DEFAULT nextval('public.etymology_etymologyid_seq'::regclass);

ALTER TABLE ONLY public.example ALTER COLUMN exampleid SET DEFAULT nextval('public.example_exampleid_seq'::regclass);

ALTER TABLE ONLY public.flashcard_levels ALTER COLUMN level_id SET DEFAULT nextval('public.flashcard_levels_level_id_seq'::regclass);

ALTER TABLE ONLY public.flashcard_quiz_options ALTER COLUMN quiz_option_id SET DEFAULT nextval('public.flashcard_quiz_options_quiz_option_id_seq'::regclass);

ALTER TABLE ONLY public.flashcard_review_history ALTER COLUMN id SET DEFAULT nextval('public.flashcard_review_history_id_seq'::regclass);

ALTER TABLE ONLY public.flashcards ALTER COLUMN id SET DEFAULT nextval('public.flashcards_id_seq'::regclass);

ALTER TABLE ONLY public.hashtags ALTER COLUMN id SET DEFAULT nextval('public.hashtags_id_seq'::regclass);

ALTER TABLE ONLY public.languages ALTER COLUMN langid SET DEFAULT nextval('public.languages_langid_seq'::regclass);

ALTER TABLE ONLY public.messages ALTER COLUMN id SET DEFAULT nextval('public.messages_id_seq'::regclass);

ALTER TABLE ONLY public.muplis ALTER COLUMN id SET DEFAULT nextval('public.muplis_id_seq'::regclass);

ALTER TABLE ONLY public.muplis_update ALTER COLUMN id SET DEFAULT nextval('public.muplis_update_id_seq'::regclass);

ALTER TABLE ONLY public.natlangwords ALTER COLUMN wordid SET DEFAULT nextval('public.natlangwords_wordid_seq'::regclass);

ALTER TABLE ONLY public.oauth_accounts ALTER COLUMN id SET DEFAULT nextval('public.oauth_accounts_id_seq'::regclass);

ALTER TABLE ONLY public.password_change_verifications ALTER COLUMN id SET DEFAULT nextval('public.password_change_verifications_id_seq'::regclass);

ALTER TABLE ONLY public.password_reset_requests ALTER COLUMN id SET DEFAULT nextval('public.password_reset_requests_id_seq'::regclass);

ALTER TABLE ONLY public.payment_audit_log ALTER COLUMN id SET DEFAULT nextval('public.payment_audit_log_id_seq'::regclass);

ALTER TABLE ONLY public.payments ALTER COLUMN id SET DEFAULT nextval('public.payments_id_seq'::regclass);

ALTER TABLE ONLY public.paypal_subscriptions ALTER COLUMN id SET DEFAULT nextval('public.paypal_subscriptions_id_seq'::regclass);

ALTER TABLE ONLY public.permissions ALTER COLUMN id SET DEFAULT nextval('public.permissions_id_seq'::regclass);

ALTER TABLE ONLY public.threads ALTER COLUMN threadid SET DEFAULT nextval('public.threads_threadid_seq'::regclass);

ALTER TABLE ONLY public.user_flashcard_progress ALTER COLUMN id SET DEFAULT nextval('public.user_flashcard_progress_id_seq'::regclass);

ALTER TABLE ONLY public.user_notifications ALTER COLUMN notification_id SET DEFAULT nextval('public.user_notifications_notification_id_seq'::regclass);

ALTER TABLE ONLY public.user_quiz_answer_history ALTER COLUMN history_id SET DEFAULT nextval('public.user_quiz_answer_history_history_id_seq'::regclass);

ALTER TABLE ONLY public.user_search_history ALTER COLUMN id SET DEFAULT nextval('public.user_search_history_id_seq'::regclass);

ALTER TABLE ONLY public.user_session_events ALTER COLUMN id SET DEFAULT nextval('public.user_session_events_id_seq'::regclass);

ALTER TABLE ONLY public.user_sessions ALTER COLUMN id SET DEFAULT nextval('public.user_sessions_id_seq'::regclass);

ALTER TABLE ONLY public.users ALTER COLUMN userid SET DEFAULT nextval('public.users_userid_seq'::regclass);

ALTER TABLE ONLY public.valsi ALTER COLUMN valsiid SET DEFAULT nextval('public.valsi_valsiid_seq'::regclass);

ALTER TABLE ONLY public.valsi_subscriptions ALTER COLUMN subscription_id SET DEFAULT nextval('public.valsi_subscriptions_subscription_id_seq'::regclass);

ALTER TABLE ONLY public.balance_transactions
    ADD CONSTRAINT balance_transactions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.cached_dictionary_exports
    ADD CONSTRAINT cached_dictionary_exports_language_tag_format_key UNIQUE (language_tag, format);

ALTER TABLE ONLY public.cached_dictionary_exports
    ADD CONSTRAINT cached_dictionary_exports_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.collection_item_images
    ADD CONSTRAINT collection_item_images_item_id_side_key UNIQUE (item_id, side);

ALTER TABLE ONLY public.collection_item_images
    ADD CONSTRAINT collection_item_images_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.collection_items
    ADD CONSTRAINT collection_items_collection_id_definition_id_key UNIQUE (collection_id, definition_id);

ALTER TABLE ONLY public.collection_items
    ADD CONSTRAINT collection_items_pkey PRIMARY KEY (item_id);

ALTER TABLE ONLY public.collections
    ADD CONSTRAINT collections_pkey PRIMARY KEY (collection_id);

ALTER TABLE ONLY public.comment_activity_counters
    ADD CONSTRAINT comment_activity_counters_pkey PRIMARY KEY (comment_id);

ALTER TABLE ONLY public.comment_bookmarks
    ADD CONSTRAINT comment_bookmarks_pkey PRIMARY KEY (comment_id, user_id);

ALTER TABLE ONLY public.comment_counters
    ADD CONSTRAINT comment_counters_pkey PRIMARY KEY (comment_id);

ALTER TABLE ONLY public.comment_likes
    ADD CONSTRAINT comment_likes_pkey PRIMARY KEY (comment_id, user_id);

ALTER TABLE ONLY public.comment_media
    ADD CONSTRAINT comment_media_pkey PRIMARY KEY (media_id);

ALTER TABLE ONLY public.comment_opinion_votes
    ADD CONSTRAINT comment_opinion_votes_pkey PRIMARY KEY (user_id, comment_id, opinion_id);

ALTER TABLE ONLY public.comment_opinions
    ADD CONSTRAINT comment_opinions_comment_id_opinion_key UNIQUE (comment_id, opinion);

ALTER TABLE ONLY public.comment_opinions
    ADD CONSTRAINT comment_opinions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.comment_reactions
    ADD CONSTRAINT comment_reactions_comment_id_user_id_reaction_key UNIQUE (comment_id, user_id, reaction);

ALTER TABLE ONLY public.comment_reactions
    ADD CONSTRAINT comment_reactions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (commentid);

ALTER TABLE ONLY public.definition_images
    ADD CONSTRAINT definition_images_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.definition_versions
    ADD CONSTRAINT definition_versions_pkey PRIMARY KEY (version_id);

ALTER TABLE ONLY public.definitions
    ADD CONSTRAINT definitions_langid_key UNIQUE (langid, valsiid, definitionnum);

ALTER TABLE ONLY public.definitions
    ADD CONSTRAINT definitions_pkey PRIMARY KEY (definitionid);

ALTER TABLE ONLY public.definitionvotes
    ADD CONSTRAINT definitionvotes_pkey PRIMARY KEY (valsiid, langid, userid, definitionid);

ALTER TABLE ONLY public.dictionary
    ADD CONSTRAINT dictionary_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.etymology
    ADD CONSTRAINT etymology_etymologyid_key UNIQUE (etymologyid);

ALTER TABLE ONLY public.example
    ADD CONSTRAINT example_exampleid_key UNIQUE (exampleid);

ALTER TABLE ONLY public.flashcard_level_items
    ADD CONSTRAINT flashcard_level_items_level_id_position_key UNIQUE (level_id, "position");

ALTER TABLE ONLY public.flashcard_level_items
    ADD CONSTRAINT flashcard_level_items_pkey PRIMARY KEY (level_id, flashcard_id);

ALTER TABLE ONLY public.flashcard_levels
    ADD CONSTRAINT flashcard_levels_collection_id_position_key UNIQUE (collection_id, "position");

ALTER TABLE ONLY public.flashcard_levels
    ADD CONSTRAINT flashcard_levels_pkey PRIMARY KEY (level_id);

ALTER TABLE ONLY public.flashcard_quiz_options
    ADD CONSTRAINT flashcard_quiz_options_pkey PRIMARY KEY (quiz_option_id);

ALTER TABLE ONLY public.flashcard_review_history
    ADD CONSTRAINT flashcard_review_history_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.flashcards
    ADD CONSTRAINT flashcards_collection_item_unique UNIQUE (collection_id, item_id);

ALTER TABLE ONLY public.flashcards
    ADD CONSTRAINT flashcards_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_pkey PRIMARY KEY (follower_id, followee_id);

ALTER TABLE ONLY public.hashtags
    ADD CONSTRAINT hashtags_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hashtags
    ADD CONSTRAINT hashtags_tag_key UNIQUE (tag);

ALTER TABLE ONLY public.keywordmapping
    ADD CONSTRAINT keywordmapping_pkey PRIMARY KEY (natlangwordid, definitionid, place);

ALTER TABLE ONLY public.languages
    ADD CONSTRAINT languages_pkey PRIMARY KEY (langid);

ALTER TABLE ONLY public.level_prerequisites
    ADD CONSTRAINT level_prerequisites_pkey PRIMARY KEY (level_id, prerequisite_id);

ALTER TABLE ONLY public.message_spam_votes
    ADD CONSTRAINT message_spam_votes_pkey PRIMARY KEY (message_id, user_id);

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.muplis
    ADD CONSTRAINT muplis_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.muplis_update
    ADD CONSTRAINT muplis_update_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.natlangwordbestplaces
    ADD CONSTRAINT natlangwordbestplaces_pkey PRIMARY KEY (wordid);

ALTER TABLE ONLY public.natlangwords
    ADD CONSTRAINT natlangwords_pkey PRIMARY KEY (wordid);

ALTER TABLE ONLY public.natlangwords
    ADD CONSTRAINT natlangwords_unique_langid_word_meaning UNIQUE (langid, word, meaning);

ALTER TABLE ONLY public.natlangwordvotes
    ADD CONSTRAINT natlangwordvotes_pkey PRIMARY KEY (natlangwordid, userid);

ALTER TABLE ONLY public.oauth_accounts
    ADD CONSTRAINT oauth_accounts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.oauth_accounts
    ADD CONSTRAINT oauth_accounts_provider_provider_id_key UNIQUE (provider, provider_id);

ALTER TABLE ONLY public.password_change_verifications
    ADD CONSTRAINT one_active_verification_per_user UNIQUE (user_id, verification_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_pkey PRIMARY KEY (pagename, version, langid);

ALTER TABLE ONLY public.password_change_verifications
    ADD CONSTRAINT password_change_verifications_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.password_change_verifications
    ADD CONSTRAINT password_change_verifications_verification_id_key UNIQUE (verification_id);

ALTER TABLE ONLY public.password_reset_requests
    ADD CONSTRAINT password_reset_requests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.password_reset_requests
    ADD CONSTRAINT password_reset_requests_session_id_key UNIQUE (session_id);

ALTER TABLE ONLY public.payment_audit_log
    ADD CONSTRAINT payment_audit_log_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_idempotency_key_key UNIQUE (idempotency_key);

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_provider_provider_payment_id_key UNIQUE (provider, provider_payment_id);

ALTER TABLE ONLY public.paypal_subscriptions
    ADD CONSTRAINT paypal_subscriptions_paypal_subscription_id_key UNIQUE (paypal_subscription_id);

ALTER TABLE ONLY public.paypal_subscriptions
    ADD CONSTRAINT paypal_subscriptions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_name_key UNIQUE (name);

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.post_hashtags
    ADD CONSTRAINT post_hashtags_pkey PRIMARY KEY (post_id, hashtag_id);

ALTER TABLE ONLY public.refinery_schema_history
    ADD CONSTRAINT refinery_schema_history_pkey PRIMARY KEY (version);

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role, permission_id);

ALTER TABLE ONLY public.threads
    ADD CONSTRAINT threads_pkey PRIMARY KEY (threadid);

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT unique_file_path UNIQUE (file_path);

ALTER TABLE ONLY public.flashcards
    ADD CONSTRAINT unique_position_per_collection UNIQUE (collection_id, "position");

ALTER TABLE ONLY public.user_balances
    ADD CONSTRAINT user_balances_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY public.user_flashcard_progress
    ADD CONSTRAINT user_flashcard_progress_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_flashcard_progress
    ADD CONSTRAINT user_flashcard_progress_unique_side UNIQUE (user_id, flashcard_id, card_side);

ALTER TABLE ONLY public.user_level_progress
    ADD CONSTRAINT user_level_progress_pkey PRIMARY KEY (user_id, level_id);

ALTER TABLE ONLY public.user_notifications
    ADD CONSTRAINT user_notifications_pkey PRIMARY KEY (notification_id);

ALTER TABLE ONLY public.user_profile_images
    ADD CONSTRAINT user_profile_images_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY public.user_quiz_answer_history
    ADD CONSTRAINT user_quiz_answer_history_pkey PRIMARY KEY (history_id);

ALTER TABLE ONLY public.user_search_history
    ADD CONSTRAINT user_search_history_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_session_events
    ADD CONSTRAINT user_session_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT user_settings_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (userid);

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);

ALTER TABLE ONLY public.valsi
    ADD CONSTRAINT valsi_pkey PRIMARY KEY (valsiid);

ALTER TABLE ONLY public.valsi_subscriptions
    ADD CONSTRAINT valsi_subscriptions_pkey PRIMARY KEY (subscription_id);

ALTER TABLE ONLY public.valsi_subscriptions
    ADD CONSTRAINT valsi_subscriptions_valsi_id_user_id_trigger_type_key UNIQUE (valsi_id, user_id, trigger_type);

ALTER TABLE ONLY public.valsi
    ADD CONSTRAINT valsi_word_source_langid_key UNIQUE (word, source_langid);

ALTER TABLE ONLY public.valsibestdefinitions
    ADD CONSTRAINT valsibestdefinitions_pkey PRIMARY KEY (valsiid, langid);

ALTER TABLE ONLY public.valsitypes
    ADD CONSTRAINT valsitypes_descriptor_key UNIQUE (descriptor);

ALTER TABLE ONLY public.valsitypes
    ADD CONSTRAINT valsitypes_pkey PRIMARY KEY (typeid);

CREATE INDEX idx_balance_transactions_user ON public.balance_transactions USING btree (user_id);

CREATE INDEX idx_balances_premium ON public.user_balances USING btree (premium_expires_at);

CREATE INDEX idx_cached_exports_cleanup ON public.cached_dictionary_exports USING btree (created_at);

CREATE INDEX idx_cached_exports_lookup ON public.cached_dictionary_exports USING btree (language_tag, format);

CREATE INDEX idx_collection_item_images_cleanup ON public.collection_item_images USING btree (created_at);

CREATE INDEX idx_collection_item_images_item ON public.collection_item_images USING btree (item_id);

CREATE INDEX idx_collection_items_collection ON public.collection_items USING btree (collection_id);

CREATE INDEX idx_collection_items_position ON public.collection_items USING btree (collection_id, "position");

CREATE INDEX idx_collections_public ON public.collections USING btree (is_public);

CREATE INDEX idx_collections_user ON public.collections USING btree (user_id);

CREATE INDEX idx_comment_bookmarks_comment ON public.comment_bookmarks USING btree (comment_id);

CREATE INDEX idx_comment_bookmarks_user ON public.comment_bookmarks USING btree (user_id);

CREATE INDEX idx_comment_counters_activity ON public.comment_activity_counters USING btree (last_activity_at DESC);

CREATE INDEX idx_comment_counters_bookmarks ON public.comment_activity_counters USING btree (total_bookmarks DESC);

CREATE INDEX idx_comment_counters_likes ON public.comment_activity_counters USING btree (total_likes DESC);

CREATE INDEX idx_comment_counters_reactions ON public.comment_activity_counters USING btree (total_reactions DESC);

CREATE INDEX idx_comment_likes_comment ON public.comment_likes USING btree (comment_id);

CREATE INDEX idx_comment_likes_user ON public.comment_likes USING btree (user_id);

CREATE INDEX idx_comment_media_comment ON public.comment_media USING btree (comment_id);

CREATE INDEX idx_comment_media_type ON public.comment_media USING btree (media_type);

CREATE INDEX idx_comment_opinion_votes_opinion ON public.comment_opinion_votes USING btree (opinion_id);

CREATE INDEX idx_comment_opinion_votes_user ON public.comment_opinion_votes USING btree (user_id);

CREATE INDEX idx_comment_opinions_comment ON public.comment_opinions USING btree (comment_id);

CREATE INDEX idx_comment_opinions_user ON public.comment_opinions USING btree (user_id);

CREATE INDEX idx_comment_reactions_comment ON public.comment_reactions USING btree (comment_id);

CREATE INDEX idx_comment_reactions_user ON public.comment_reactions USING btree (user_id);

CREATE INDEX idx_comments_threadid ON public.comments USING btree (threadid);

CREATE INDEX idx_definition_images_definition_id ON public.definition_images USING btree (definition_id);

CREATE INDEX idx_definition_versions_created_at ON public.definition_versions USING btree (created_at);

CREATE INDEX idx_definition_versions_definition_id ON public.definition_versions USING btree (definition_id);

CREATE INDEX idx_definitions_created_at ON public.definitions USING btree (created_at);

CREATE INDEX idx_definitions_etymology ON public.definitions USING btree (etymology) WHERE (etymology IS NOT NULL);

CREATE INDEX idx_definitions_langid ON public.definitions USING btree (langid);

CREATE INDEX idx_definitions_userid ON public.definitions USING btree (userid);

CREATE INDEX idx_definitions_valsiid_time ON public.definitions USING btree (valsiid, "time" DESC);

CREATE INDEX idx_definitionvotes_defid ON public.definitionvotes USING btree (definitionid);

CREATE INDEX idx_definitionvotes_userid_defid ON public.definitionvotes USING btree (userid, definitionid);

CREATE INDEX idx_dictionary_d ON public.dictionary USING gin (d public.gin_trgm_ops);

CREATE INDEX idx_dictionary_w ON public.dictionary USING gin (w public.gin_trgm_ops);

CREATE INDEX idx_flashcard_level_items_flashcard ON public.flashcard_level_items USING btree (flashcard_id);

CREATE INDEX idx_flashcard_progress_archived ON public.user_flashcard_progress USING btree (archived);

CREATE INDEX idx_flashcard_progress_side ON public.user_flashcard_progress USING btree (flashcard_id, user_id, card_side);

CREATE INDEX idx_flashcard_review_history_lookup ON public.flashcard_review_history USING btree (user_id, flashcard_id, review_time);

CREATE INDEX idx_flashcards_collection ON public.flashcards USING btree (collection_id);

CREATE INDEX idx_flashcards_item_id ON public.flashcards USING btree (item_id);

CREATE INDEX idx_flashcards_position ON public.flashcards USING btree (collection_id, "position");

CREATE INDEX idx_hashtags_tag ON public.hashtags USING btree (tag);

CREATE INDEX idx_level_prerequisites_level ON public.level_prerequisites USING btree (level_id);

CREATE INDEX idx_level_progress_completion ON public.user_level_progress USING btree (user_id, level_id) WHERE (completed_at IS NOT NULL);

CREATE INDEX idx_level_progress_user ON public.user_level_progress USING btree (user_id);

CREATE INDEX idx_message_spam_votes_message_id ON public.message_spam_votes USING btree (message_id);

CREATE INDEX idx_messages_cleaned_subject ON public.messages USING btree (cleaned_subject);

CREATE INDEX idx_messages_content ON public.messages USING gin (content public.gin_trgm_ops);

CREATE INDEX idx_messages_file_path ON public.messages USING btree (file_path);

CREATE INDEX idx_messages_subject ON public.messages USING gin (subject public.gin_trgm_ops);

CREATE INDEX idx_muplis_english ON public.muplis USING gin (english public.gin_trgm_ops);

CREATE INDEX idx_muplis_lojban ON public.muplis USING gin (lojban public.gin_trgm_ops);

CREATE INDEX idx_notifications_pending_email ON public.user_notifications USING btree (email_sent) WHERE (email_sent IS NULL);

CREATE INDEX idx_notifications_user ON public.user_notifications USING btree (user_id, created_at);

CREATE INDEX idx_password_change_cleanup ON public.password_change_verifications USING btree (expires_at) WHERE (completed_at IS NULL);

CREATE INDEX idx_password_change_user ON public.password_change_verifications USING btree (user_id) WHERE (completed_at IS NULL);

CREATE INDEX idx_password_reset_email_created ON public.password_reset_requests USING btree (email, created_at);

CREATE INDEX idx_password_reset_session_token ON public.password_reset_requests USING btree (session_id, token);

CREATE INDEX idx_payment_audit_payment ON public.payment_audit_log USING btree (payment_id);

CREATE INDEX idx_payment_audit_user ON public.payment_audit_log USING btree (user_id);

CREATE INDEX idx_payments_idempotency ON public.payments USING btree (idempotency_key);

CREATE INDEX idx_payments_provider_id ON public.payments USING btree (provider, provider_payment_id);

CREATE INDEX idx_payments_status ON public.payments USING btree (status);

CREATE INDEX idx_payments_user ON public.payments USING btree (user_id);

CREATE INDEX idx_paypal_subscriptions_paypal_subscription_id ON public.paypal_subscriptions USING btree (paypal_subscription_id);

CREATE INDEX idx_paypal_subscriptions_user_id ON public.paypal_subscriptions USING btree (user_id);

CREATE INDEX idx_post_hashtags_hashtag ON public.post_hashtags USING btree (hashtag_id);

CREATE INDEX idx_post_hashtags_post ON public.post_hashtags USING btree (post_id);

CREATE INDEX idx_search_history_created ON public.user_search_history USING btree (created_at);

CREATE INDEX idx_search_history_user ON public.user_search_history USING btree (user_id);

CREATE INDEX idx_threads_target_user_id ON public.threads USING btree (target_user_id) WHERE (target_user_id IS NOT NULL);

CREATE INDEX idx_threads_valsiid_defid ON public.threads USING btree (valsiid, definitionid);

CREATE UNIQUE INDEX idx_unique_active_progress ON public.user_flashcard_progress USING btree (user_id, flashcard_id, card_side) WHERE (NOT archived);

CREATE INDEX idx_user_progress_next_review ON public.user_flashcard_progress USING btree (next_review_at);

CREATE INDEX idx_user_progress_status ON public.user_flashcard_progress USING btree (status);

CREATE INDEX idx_user_progress_user ON public.user_flashcard_progress USING btree (user_id);

CREATE INDEX idx_user_quiz_answer_history_flashcard_selected_option ON public.user_quiz_answer_history USING btree (flashcard_id, selected_option_text);

CREATE INDEX idx_user_quiz_answer_history_user_flashcard ON public.user_quiz_answer_history USING btree (user_id, flashcard_id);

CREATE INDEX idx_user_session_events_event_timestamp ON public.user_session_events USING btree (event_timestamp);

CREATE INDEX idx_user_session_events_event_type ON public.user_session_events USING btree (event_type);

CREATE INDEX idx_user_session_events_session_id ON public.user_session_events USING btree (session_id);

CREATE INDEX idx_user_sessions_ended_at ON public.user_sessions USING btree (ended_at);

CREATE INDEX idx_user_sessions_last_active_at ON public.user_sessions USING btree (last_active_at);

CREATE UNIQUE INDEX idx_user_sessions_session_uuid ON public.user_sessions USING btree (session_uuid);

CREATE INDEX idx_user_sessions_started_at ON public.user_sessions USING btree (started_at);

CREATE INDEX idx_user_sessions_user_id ON public.user_sessions USING btree (user_id);

CREATE INDEX idx_user_settings_user_id ON public.user_settings USING btree (user_id);

CREATE INDEX idx_users_email_confirmed ON public.users USING btree (email_confirmed);

CREATE INDEX idx_users_email_token ON public.users USING btree (email_confirmation_token) WHERE (email_confirmation_token IS NOT NULL);

CREATE INDEX idx_users_role ON public.users USING btree (role);

CREATE INDEX idx_valsi_subs_user ON public.valsi_subscriptions USING btree (user_id);

CREATE INDEX idx_valsi_subs_valsi_user ON public.valsi_subscriptions USING btree (valsi_id, user_id);

CREATE INDEX idx_valsi_typeid ON public.valsi USING btree (typeid);

CREATE INDEX natlangwordbestplaces_definitionid_key ON public.natlangwordbestplaces USING btree (definitionid);

CREATE INDEX natlangwords_lower_word ON public.natlangwords USING btree (lower(word));

CREATE UNIQUE INDEX natlangwords_unique_langid_word_null ON public.natlangwords USING btree (langid, word) WHERE (meaning IS NULL);

CREATE UNIQUE INDEX uq_flashcard_quiz_options_flashcard_id ON public.flashcard_quiz_options USING btree (flashcard_id);

CREATE UNIQUE INDEX user_reaction_counts_idx ON public.user_reaction_counts USING btree (user_id, comment_id);

CREATE INDEX valsi_lower_word ON public.valsi USING btree (lower(word));

CREATE UNIQUE INDEX valsi_unique_word_nospaces ON public.valsi USING btree (replace(word, ' '::text, ''::text));

CREATE INDEX valsibestdefinitions_definitionid_key ON public.valsibestdefinitions USING btree (definitionid);

CREATE TRIGGER after_flashcard_review AFTER INSERT ON public.flashcard_review_history FOR EACH ROW EXECUTE FUNCTION public.update_level_progress();

CREATE TRIGGER cleanup_collection_item_images BEFORE DELETE ON public.collection_items FOR EACH ROW EXECUTE FUNCTION public.cleanup_item_images();

CREATE TRIGGER cleanup_definition_images BEFORE DELETE ON public.definitions FOR EACH ROW EXECUTE FUNCTION public.cleanup_orphaned_images();

CREATE TRIGGER comment_stats_trigger AFTER INSERT OR DELETE OR UPDATE ON public.comments FOR EACH ROW EXECUTE FUNCTION public.update_thread_stats();

CREATE TRIGGER comment_subscription_trigger AFTER INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION public.auto_subscribe_on_content();

CREATE TRIGGER definition_subscription_trigger AFTER INSERT ON public.definitions FOR EACH ROW EXECUTE FUNCTION public.auto_subscribe_on_content();

CREATE TRIGGER ensure_user_balance AFTER INSERT ON public.users FOR EACH ROW EXECUTE FUNCTION public.create_user_balance();

CREATE TRIGGER maintain_comment_reply_count AFTER INSERT OR DELETE ON public.comments FOR EACH ROW EXECUTE FUNCTION public.update_comment_reply_count();

CREATE TRIGGER maintain_premium_status BEFORE UPDATE ON public.user_balances FOR EACH ROW EXECUTE FUNCTION public.update_premium_status();

CREATE TRIGGER message_sent_at_trigger BEFORE INSERT OR UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION public.set_message_sent_at();

CREATE TRIGGER natlangwords_cleanup_trigger AFTER INSERT OR UPDATE ON public.natlangwords FOR EACH ROW EXECUTE FUNCTION public.trigger_cleanup_natlangwords();

CREATE TRIGGER on_definitionvotes_delete AFTER DELETE ON public.definitionvotes FOR EACH ROW EXECUTE FUNCTION public.refresh_valsibestdefinitions_for_delete();

CREATE TRIGGER on_definitionvotes_insert AFTER INSERT ON public.definitionvotes FOR EACH ROW EXECUTE FUNCTION public.refresh_valsibestdefinitions_for_upsert();

CREATE TRIGGER on_definitionvotes_update AFTER UPDATE ON public.definitionvotes FOR EACH ROW EXECUTE FUNCTION public.refresh_valsibestdefinitions_for_upsert();

CREATE TRIGGER on_natlangwordvotes_delete AFTER DELETE ON public.natlangwordvotes FOR EACH ROW EXECUTE FUNCTION public.refresh_natlangwordbestplaces_for_delete();

CREATE TRIGGER on_natlangwordvotes_insert AFTER INSERT ON public.natlangwordvotes FOR EACH ROW EXECUTE FUNCTION public.refresh_natlangwordbestplaces_for_upsert();

CREATE TRIGGER on_natlangwordvotes_update AFTER UPDATE ON public.natlangwordvotes FOR EACH ROW EXECUTE FUNCTION public.refresh_natlangwordbestplaces_for_upsert();

CREATE TRIGGER prevent_admin_role_deletion_trigger BEFORE DELETE ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION public.prevent_admin_role_deletion();

CREATE TRIGGER set_timestamp_collection_items BEFORE UPDATE ON public.collection_items FOR EACH ROW EXECUTE FUNCTION public.trigger_set_collection_item_timestamp();

CREATE TRIGGER set_timestamp_paypal_subscriptions BEFORE UPDATE ON public.paypal_subscriptions FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();

CREATE TRIGGER trg_sync_admin_after_permission_changes AFTER INSERT OR DELETE OR UPDATE ON public.permissions FOR EACH STATEMENT EXECUTE FUNCTION public.sync_admin_permissions();

CREATE TRIGGER trg_sync_admin_after_role_perms_changes AFTER DELETE OR UPDATE ON public.role_permissions FOR EACH ROW WHEN ((old.role = 'admin'::text)) EXECUTE FUNCTION public.sync_admin_permissions();

CREATE TRIGGER update_cleaned_subject BEFORE INSERT OR UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION public.update_cleaned_subject();

CREATE TRIGGER update_comment_activity_timestamp BEFORE UPDATE ON public.comment_activity_counters FOR EACH ROW EXECUTE FUNCTION public.update_comment_activity_timestamp();

CREATE TRIGGER update_comment_counter_timestamp BEFORE UPDATE ON public.comment_counters FOR EACH ROW EXECUTE FUNCTION public.update_comment_counter_timestamp();

CREATE TRIGGER update_followers_count AFTER INSERT OR DELETE ON public.follows FOR EACH ROW EXECUTE FUNCTION public.update_followers_count();

CREATE TRIGGER update_plain_content BEFORE INSERT OR UPDATE OF content ON public.comments FOR EACH ROW EXECUTE FUNCTION public.extract_plain_content();

CREATE TRIGGER update_reaction_count AFTER INSERT OR DELETE ON public.comment_reactions FOR EACH ROW EXECUTE FUNCTION public.update_reaction_count();

CREATE TRIGGER update_reaction_counts AFTER INSERT OR DELETE ON public.comment_reactions FOR EACH STATEMENT EXECUTE FUNCTION public.refresh_reaction_counts();

ALTER TABLE ONLY public.valsi
    ADD CONSTRAINT "$1" FOREIGN KEY (typeid) REFERENCES public.valsitypes(typeid);

ALTER TABLE ONLY public.keywordmapping
    ADD CONSTRAINT "$1" FOREIGN KEY (natlangwordid) REFERENCES public.natlangwords(wordid);

ALTER TABLE ONLY public.natlangwordvotes
    ADD CONSTRAINT "$1" FOREIGN KEY (natlangwordid) REFERENCES public.natlangwords(wordid);

ALTER TABLE ONLY public.keywordmapping
    ADD CONSTRAINT "$2" FOREIGN KEY (definitionid) REFERENCES public.definitions(definitionid);

ALTER TABLE ONLY public.natlangwordvotes
    ADD CONSTRAINT "$2" FOREIGN KEY (definitionid) REFERENCES public.definitions(definitionid);

ALTER TABLE ONLY public.natlangwordvotes
    ADD CONSTRAINT "$3" FOREIGN KEY (userid) REFERENCES public.users(userid);

ALTER TABLE ONLY public.balance_transactions
    ADD CONSTRAINT balance_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.collection_item_images
    ADD CONSTRAINT collection_item_images_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.collection_items(item_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.collection_items
    ADD CONSTRAINT collection_items_collection_id_fkey FOREIGN KEY (collection_id) REFERENCES public.collections(collection_id);

ALTER TABLE ONLY public.collection_items
    ADD CONSTRAINT collection_items_definition_id_fkey FOREIGN KEY (definition_id) REFERENCES public.definitions(definitionid);

ALTER TABLE ONLY public.collection_items
    ADD CONSTRAINT collection_items_langid_fkey FOREIGN KEY (langid) REFERENCES public.languages(langid);

ALTER TABLE ONLY public.collection_items
    ADD CONSTRAINT collection_items_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.collections
    ADD CONSTRAINT collections_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.comment_activity_counters
    ADD CONSTRAINT comment_activity_counters_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(commentid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_bookmarks
    ADD CONSTRAINT comment_bookmarks_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(commentid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_bookmarks
    ADD CONSTRAINT comment_bookmarks_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_counters
    ADD CONSTRAINT comment_counters_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(commentid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_likes
    ADD CONSTRAINT comment_likes_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(commentid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_likes
    ADD CONSTRAINT comment_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_media
    ADD CONSTRAINT comment_media_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(commentid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_opinion_votes
    ADD CONSTRAINT comment_opinion_votes_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(commentid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_opinion_votes
    ADD CONSTRAINT comment_opinion_votes_opinion_id_fkey FOREIGN KEY (opinion_id) REFERENCES public.comment_opinions(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_opinion_votes
    ADD CONSTRAINT comment_opinion_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_opinions
    ADD CONSTRAINT comment_opinions_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(commentid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_opinions
    ADD CONSTRAINT comment_opinions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_reactions
    ADD CONSTRAINT comment_reactions_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(commentid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comment_reactions
    ADD CONSTRAINT comment_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_parentid FOREIGN KEY (parentid) REFERENCES public.comments(commentid) MATCH FULL;

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_threadid FOREIGN KEY (threadid) REFERENCES public.threads(threadid) MATCH FULL;

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_userid FOREIGN KEY (userid) REFERENCES public.users(userid) MATCH FULL;

ALTER TABLE ONLY public.definition_images
    ADD CONSTRAINT definition_images_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(userid);

ALTER TABLE ONLY public.definition_images
    ADD CONSTRAINT definition_images_definition_id_fkey FOREIGN KEY (definition_id) REFERENCES public.definitions(definitionid) ON DELETE CASCADE;

ALTER TABLE ONLY public.definition_versions
    ADD CONSTRAINT definition_versions_definition_id_fkey FOREIGN KEY (definition_id) REFERENCES public.definitions(definitionid);

ALTER TABLE ONLY public.definition_versions
    ADD CONSTRAINT definition_versions_langid_fkey FOREIGN KEY (langid) REFERENCES public.languages(langid);

ALTER TABLE ONLY public.definition_versions
    ADD CONSTRAINT definition_versions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.definition_versions
    ADD CONSTRAINT definition_versions_valsiid_fkey FOREIGN KEY (valsiid) REFERENCES public.valsi(valsiid);

ALTER TABLE ONLY public.definitions
    ADD CONSTRAINT definitions_langid FOREIGN KEY (langid) REFERENCES public.languages(langid) MATCH FULL;

ALTER TABLE ONLY public.definitions
    ADD CONSTRAINT definitions_userid FOREIGN KEY (userid) REFERENCES public.users(userid) MATCH FULL;

ALTER TABLE ONLY public.definitions
    ADD CONSTRAINT definitions_valsiid FOREIGN KEY (valsiid) REFERENCES public.valsi(valsiid) MATCH FULL;

ALTER TABLE ONLY public.definitionvotes
    ADD CONSTRAINT definitionvotes_definitionid FOREIGN KEY (definitionid) REFERENCES public.definitions(definitionid) MATCH FULL;

ALTER TABLE ONLY public.definitionvotes
    ADD CONSTRAINT definitionvotes_langid FOREIGN KEY (langid) REFERENCES public.languages(langid) MATCH FULL;

ALTER TABLE ONLY public.definitionvotes
    ADD CONSTRAINT definitionvotes_userid FOREIGN KEY (userid) REFERENCES public.users(userid) MATCH FULL;

ALTER TABLE ONLY public.definitionvotes
    ADD CONSTRAINT definitionvotes_valsiid FOREIGN KEY (valsiid) REFERENCES public.valsi(valsiid) MATCH FULL;

ALTER TABLE ONLY public.etymology
    ADD CONSTRAINT etymology_langid FOREIGN KEY (langid) REFERENCES public.languages(langid) MATCH FULL;

ALTER TABLE ONLY public.etymology
    ADD CONSTRAINT etymology_userid FOREIGN KEY (userid) REFERENCES public.users(userid) MATCH FULL;

ALTER TABLE ONLY public.etymology
    ADD CONSTRAINT etymology_valsiid FOREIGN KEY (valsiid) REFERENCES public.valsi(valsiid) MATCH FULL;

ALTER TABLE ONLY public.example
    ADD CONSTRAINT example_userid FOREIGN KEY (userid) REFERENCES public.users(userid) MATCH FULL;

ALTER TABLE ONLY public.example
    ADD CONSTRAINT example_valsiid FOREIGN KEY (valsiid) REFERENCES public.valsi(valsiid) MATCH FULL;

ALTER TABLE ONLY public.message_spam_votes
    ADD CONSTRAINT fk_message FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_session_events
    ADD CONSTRAINT fk_session FOREIGN KEY (session_id) REFERENCES public.user_sessions(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.message_spam_votes
    ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.flashcard_level_items
    ADD CONSTRAINT flashcard_level_items_flashcard_id_fkey FOREIGN KEY (flashcard_id) REFERENCES public.flashcards(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.flashcard_level_items
    ADD CONSTRAINT flashcard_level_items_level_id_fkey FOREIGN KEY (level_id) REFERENCES public.flashcard_levels(level_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.flashcard_levels
    ADD CONSTRAINT flashcard_levels_collection_id_fkey FOREIGN KEY (collection_id) REFERENCES public.collections(collection_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.flashcard_quiz_options
    ADD CONSTRAINT flashcard_quiz_options_flashcard_id_fkey FOREIGN KEY (flashcard_id) REFERENCES public.flashcards(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.flashcard_review_history
    ADD CONSTRAINT flashcard_review_history_flashcard_id_fkey FOREIGN KEY (flashcard_id) REFERENCES public.flashcards(id);

ALTER TABLE ONLY public.flashcard_review_history
    ADD CONSTRAINT flashcard_review_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.flashcard_review_history
    ADD CONSTRAINT flashcard_review_history_user_progress_fkey FOREIGN KEY (user_id, flashcard_id, card_side) REFERENCES public.user_flashcard_progress(user_id, flashcard_id, card_side);

ALTER TABLE ONLY public.flashcards
    ADD CONSTRAINT flashcards_collection_id_fkey FOREIGN KEY (collection_id) REFERENCES public.collections(collection_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.flashcards
    ADD CONSTRAINT flashcards_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.collection_items(item_id);

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_followee_id_fkey FOREIGN KEY (followee_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.keywordmapping
    ADD CONSTRAINT keywordmapping_defbestguessid FOREIGN KEY (definitionid) REFERENCES public.definitions(definitionid) MATCH FULL;

ALTER TABLE ONLY public.keywordmapping
    ADD CONSTRAINT keywordmapping_natlangwordid FOREIGN KEY (natlangwordid) REFERENCES public.natlangwords(wordid) MATCH FULL;

ALTER TABLE ONLY public.level_prerequisites
    ADD CONSTRAINT level_prerequisites_level_id_fkey FOREIGN KEY (level_id) REFERENCES public.flashcard_levels(level_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.level_prerequisites
    ADD CONSTRAINT level_prerequisites_prerequisite_id_fkey FOREIGN KEY (prerequisite_id) REFERENCES public.flashcard_levels(level_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.natlangwordbestplaces
    ADD CONSTRAINT natlangwordbestplaces_definitionid FOREIGN KEY (definitionid) REFERENCES public.definitions(definitionid);

ALTER TABLE ONLY public.natlangwordbestplaces
    ADD CONSTRAINT natlangwordbestplaces_wordid FOREIGN KEY (wordid) REFERENCES public.natlangwords(wordid);

ALTER TABLE ONLY public.threads
    ADD CONSTRAINT natlangwordid_natlangwordid FOREIGN KEY (natlangwordid) REFERENCES public.natlangwords(wordid) MATCH FULL;

ALTER TABLE ONLY public.natlangwords
    ADD CONSTRAINT natlangwords_langid FOREIGN KEY (langid) REFERENCES public.languages(langid) MATCH FULL;

ALTER TABLE ONLY public.natlangwordvotes
    ADD CONSTRAINT natlangwordvotes_natlangwordid FOREIGN KEY (natlangwordid) REFERENCES public.natlangwords(wordid) MATCH FULL;

ALTER TABLE ONLY public.natlangwordvotes
    ADD CONSTRAINT natlangwordvotes_voter FOREIGN KEY (userid) REFERENCES public.users(userid) MATCH FULL;

ALTER TABLE ONLY public.oauth_accounts
    ADD CONSTRAINT oauth_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_langid FOREIGN KEY (langid) REFERENCES public.languages(langid) MATCH FULL;

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_userid FOREIGN KEY (userid) REFERENCES public.users(userid) MATCH FULL;

ALTER TABLE ONLY public.password_change_verifications
    ADD CONSTRAINT password_change_verifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.payment_audit_log
    ADD CONSTRAINT payment_audit_log_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id);

ALTER TABLE ONLY public.payment_audit_log
    ADD CONSTRAINT payment_audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.paypal_subscriptions
    ADD CONSTRAINT paypal_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.post_hashtags
    ADD CONSTRAINT post_hashtags_hashtag_id_fkey FOREIGN KEY (hashtag_id) REFERENCES public.hashtags(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.post_hashtags
    ADD CONSTRAINT post_hashtags_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.comments(commentid) ON DELETE CASCADE;

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.threads
    ADD CONSTRAINT threads_creator_user_id_fkey FOREIGN KEY (creator_user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.threads
    ADD CONSTRAINT threads_last_comment_id_fkey FOREIGN KEY (last_comment_id) REFERENCES public.comments(commentid);

ALTER TABLE ONLY public.threads
    ADD CONSTRAINT threads_last_comment_user_id_fkey FOREIGN KEY (last_comment_user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.threads
    ADD CONSTRAINT threads_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.threads
    ADD CONSTRAINT threads_valsiid FOREIGN KEY (valsiid) REFERENCES public.valsi(valsiid) MATCH FULL;

ALTER TABLE ONLY public.user_balances
    ADD CONSTRAINT user_balances_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.user_flashcard_progress
    ADD CONSTRAINT user_flashcard_progress_flashcard_id_fkey FOREIGN KEY (flashcard_id) REFERENCES public.flashcards(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_flashcard_progress
    ADD CONSTRAINT user_flashcard_progress_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_level_progress
    ADD CONSTRAINT user_level_progress_level_id_fkey FOREIGN KEY (level_id) REFERENCES public.flashcard_levels(level_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_level_progress
    ADD CONSTRAINT user_level_progress_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_notifications
    ADD CONSTRAINT user_notifications_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.user_notifications
    ADD CONSTRAINT user_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.user_notifications
    ADD CONSTRAINT user_notifications_valsi_id_fkey FOREIGN KEY (valsi_id) REFERENCES public.valsi(valsiid);

ALTER TABLE ONLY public.user_profile_images
    ADD CONSTRAINT user_profile_images_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.user_quiz_answer_history
    ADD CONSTRAINT user_quiz_answer_history_flashcard_id_fkey FOREIGN KEY (flashcard_id) REFERENCES public.flashcards(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_quiz_answer_history
    ADD CONSTRAINT user_quiz_answer_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_search_history
    ADD CONSTRAINT user_search_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid) ON DELETE SET NULL;

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT user_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_disabled_by_fkey FOREIGN KEY (disabled_by) REFERENCES public.users(userid);

ALTER TABLE ONLY public.valsi
    ADD CONSTRAINT valsi_source_langid_fkey FOREIGN KEY (source_langid) REFERENCES public.languages(langid);

ALTER TABLE ONLY public.valsi_subscriptions
    ADD CONSTRAINT valsi_subscriptions_source_comment_id_fkey FOREIGN KEY (source_comment_id) REFERENCES public.comments(commentid);

ALTER TABLE ONLY public.valsi_subscriptions
    ADD CONSTRAINT valsi_subscriptions_source_definition_id_fkey FOREIGN KEY (source_definition_id) REFERENCES public.definitions(definitionid);

ALTER TABLE ONLY public.valsi_subscriptions
    ADD CONSTRAINT valsi_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(userid);

ALTER TABLE ONLY public.valsi_subscriptions
    ADD CONSTRAINT valsi_subscriptions_valsi_id_fkey FOREIGN KEY (valsi_id) REFERENCES public.valsi(valsiid);

ALTER TABLE ONLY public.valsi
    ADD CONSTRAINT valsi_userid FOREIGN KEY (userid) REFERENCES public.users(userid) MATCH FULL;

ALTER TABLE ONLY public.valsibestdefinitions
    ADD CONSTRAINT valsibestdefinitions_definitionid FOREIGN KEY (definitionid) REFERENCES public.definitions(definitionid);

ALTER TABLE ONLY public.valsibestdefinitions
    ADD CONSTRAINT valsibestdefinitions_langid FOREIGN KEY (langid) REFERENCES public.languages(langid);

ALTER TABLE ONLY public.valsibestdefinitions
    ADD CONSTRAINT valsibestdefinitions_valsiid FOREIGN KEY (valsiid) REFERENCES public.valsi(valsiid);

GRANT SELECT ON TABLE public.comments TO PUBLIC;

GRANT SELECT ON TABLE public.threads TO PUBLIC;

GRANT SELECT ON TABLE public.users TO PUBLIC;

GRANT SELECT ON TABLE public.definitions TO PUBLIC;

GRANT SELECT ON TABLE public.languages TO PUBLIC;

GRANT SELECT ON TABLE public.valsi TO PUBLIC;

GRANT SELECT ON TABLE public.etymology TO PUBLIC;

GRANT SELECT ON TABLE public.convenientetymology TO PUBLIC;

GRANT SELECT ON TABLE public.example TO PUBLIC;

GRANT SELECT ON TABLE public.convenientexamples TO PUBLIC;

GRANT SELECT ON TABLE public.natlangwords TO PUBLIC;

GRANT SELECT ON TABLE public.convenientthreads TO PUBLIC;

GRANT SELECT ON TABLE public.valsitypes TO PUBLIC;

GRANT SELECT ON TABLE public.convenientvalsi TO PUBLIC;

GRANT SELECT ON TABLE public.definitionvotes TO PUBLIC;

GRANT SELECT ON TABLE public.keywordmapping TO PUBLIC;

GRANT SELECT ON TABLE public.natlangwordvotes TO PUBLIC;

GRANT SELECT ON TABLE public.pages TO PUBLIC;

GRANT SELECT ON TABLE public.xrefs TO PUBLIC;



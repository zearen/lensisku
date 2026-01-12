-- Create levels table
CREATE TABLE flashcard_levels (
    level_id SERIAL PRIMARY KEY,
    collection_id INTEGER NOT NULL REFERENCES collections(collection_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    min_cards INTEGER NOT NULL DEFAULT 5,
    min_success_rate FLOAT NOT NULL DEFAULT 0.8,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(collection_id, position)
);

-- Create level prerequisites
CREATE TABLE level_prerequisites (
    level_id INTEGER REFERENCES flashcard_levels(level_id) ON DELETE CASCADE,
    prerequisite_id INTEGER REFERENCES flashcard_levels(level_id) ON DELETE CASCADE,
    PRIMARY KEY (level_id, prerequisite_id),
    CHECK (level_id != prerequisite_id)
);

-- Create table to map flashcards to levels
CREATE TABLE flashcard_level_items (
    level_id INTEGER REFERENCES flashcard_levels(level_id) ON DELETE CASCADE,
    flashcard_id INTEGER REFERENCES flashcards(id) ON DELETE CASCADE,
    position INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (level_id, flashcard_id),
    UNIQUE(level_id, position)
);

-- Track user progress through levels
CREATE TABLE user_level_progress (
    user_id INTEGER REFERENCES users(userid) ON DELETE CASCADE,
    level_id INTEGER REFERENCES flashcard_levels(level_id) ON DELETE CASCADE,
    cards_completed INTEGER NOT NULL DEFAULT 0,
    correct_answers INTEGER NOT NULL DEFAULT 0,
    total_answers INTEGER NOT NULL DEFAULT 0,
    unlocked_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, level_id)
);

-- Create functions to check level completion
CREATE OR REPLACE FUNCTION check_level_prerequisites(
    p_user_id INTEGER,
    p_level_id INTEGER
) RETURNS BOOLEAN AS $$
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
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_level_completion(
    p_user_id INTEGER,
    p_level_id INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
    v_min_cards INTEGER;
    v_min_success_rate FLOAT;
    v_completion_rate FLOAT;
    v_cards_completed INTEGER;
BEGIN
    -- Get level requirements
    SELECT min_cards, min_success_rate
    INTO v_min_cards, v_min_success_rate
    FROM flashcard_levels
    WHERE level_id = p_level_id;
    
    -- Get user progress
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
$$ LANGUAGE plpgsql;

-- Create trigger to update level progress
CREATE OR REPLACE FUNCTION update_level_progress()
RETURNS TRIGGER AS $$
BEGIN
    -- Update user level progress when a review is recorded
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

    -- Set unlocked_at for levels where prerequisites are met
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_flashcard_review
    AFTER INSERT ON flashcard_review_history
    FOR EACH ROW
    EXECUTE FUNCTION update_level_progress();

-- Create indexes for performance
CREATE INDEX idx_flashcard_level_items_flashcard 
ON flashcard_level_items(flashcard_id);

CREATE INDEX idx_level_progress_user 
ON user_level_progress(user_id);

CREATE INDEX idx_level_progress_completion 
ON user_level_progress(user_id, level_id) 
WHERE completed_at IS NOT NULL;

CREATE INDEX idx_level_prerequisites_level 
ON level_prerequisites(level_id);
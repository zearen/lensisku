-- V107_add_quiz_flashcard_type.sql

-- Add new enum values to flashcard_direction
-- Note: Adding values to an ENUM is generally safe.
-- If this were more complex (e.g., renaming, removing), a more involved process
-- like creating a new type, migrating data, and swapping types would be needed.
ALTER TYPE public.flashcard_direction ADD VALUE IF NOT EXISTS 'quiz_direct';
ALTER TYPE public.flashcard_direction ADD VALUE IF NOT EXISTS 'quiz_reverse';
ALTER TYPE public.flashcard_direction ADD VALUE IF NOT EXISTS 'quiz_both';

-- Table to store the author-provided correct answer for a quiz flashcard
CREATE TABLE public.flashcard_quiz_options (
    quiz_option_id SERIAL PRIMARY KEY,
    flashcard_id INTEGER NOT NULL REFERENCES public.flashcards(id) ON DELETE CASCADE,
    correct_answer_text TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- A flashcard should only have one set of correct answer defined.
CREATE UNIQUE INDEX uq_flashcard_quiz_options_flashcard_id ON public.flashcard_quiz_options(flashcard_id);

-- Table to store user's answers to quiz questions for exploitation/exploration
CREATE TABLE public.user_quiz_answer_history (
    history_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES public.users(userid) ON DELETE CASCADE,
    flashcard_id INTEGER NOT NULL REFERENCES public.flashcards(id) ON DELETE CASCADE,
    selected_option_text TEXT NOT NULL,
    is_correct_selection BOOLEAN NOT NULL,
    presented_options JSONB, -- Array of all 4 options presented to the user, e.g., ["opt1", "opt2", "opt3", "opt4"]
    answered_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_user_quiz_answer_history_user_flashcard ON public.user_quiz_answer_history(user_id, flashcard_id);
CREATE INDEX idx_user_quiz_answer_history_flashcard_selected_option ON public.user_quiz_answer_history(flashcard_id, selected_option_text);


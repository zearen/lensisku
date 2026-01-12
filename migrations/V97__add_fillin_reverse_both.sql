-- Add new values to the flashcard_direction enum
ALTER TYPE public.flashcard_direction ADD VALUE IF NOT EXISTS 'fillin_reverse';
ALTER TYPE public.flashcard_direction ADD VALUE IF NOT EXISTS 'fillin_both';

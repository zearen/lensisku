-- Add FillIn as a new value to the flashcard_direction enum
ALTER TYPE public.flashcard_direction ADD VALUE IF NOT EXISTS 'fillin';

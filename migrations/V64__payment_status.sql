BEGIN;

-- Create a new enum type with the additional value
CREATE TYPE payment_status_new AS ENUM ('pending', 'succeeded', 'failed', 'faulty');

-- First remove the default constraint
ALTER TABLE payments ALTER COLUMN status DROP DEFAULT;

-- Then update the column type
ALTER TABLE payments 
  ALTER COLUMN status TYPE payment_status_new 
  USING status::text::payment_status_new;

-- Add back the default constraint with the new type
ALTER TABLE payments ALTER COLUMN status SET DEFAULT 'pending';

-- Drop the old type
DROP TYPE payment_status;

-- Rename the new type to the original name
ALTER TYPE payment_status_new RENAME TO payment_status;

COMMIT;
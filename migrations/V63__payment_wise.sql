BEGIN;
  -- Lock the table that uses the enum to prevent any data modifications during the alter type
  LOCK TABLE payments IN EXCLUSIVE MODE;
  
  -- Add the new enum value
  ALTER TYPE payment_provider ADD VALUE 'wise';
COMMIT;
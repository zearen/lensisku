BEGIN;

-- Drop the existing primary key constraint
ALTER TABLE definitionvotes 
DROP CONSTRAINT definitionvotes_pkey;

-- Add the new primary key constraint including definitionid
ALTER TABLE definitionvotes
ADD CONSTRAINT definitionvotes_pkey 
PRIMARY KEY (valsiid, langid, userid, definitionid);

COMMIT;
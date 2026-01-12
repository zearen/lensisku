-- Delete threads that have no associated comments
DELETE FROM threads
WHERE threadid NOT IN (
    SELECT DISTINCT threadid 
    FROM comments
);

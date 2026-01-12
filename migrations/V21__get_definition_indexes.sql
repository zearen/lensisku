-- Index for base query performance
CREATE INDEX IF NOT EXISTS idx_definitions_valsiid_time ON definitions(valsiid, time DESC);

-- Index for looking up threads and comments
CREATE INDEX IF NOT EXISTS idx_threads_valsiid_defid ON threads(valsiid, definitionid);
CREATE INDEX IF NOT EXISTS idx_comments_threadid ON comments(threadid);

-- Index for vote calculations
CREATE INDEX IF NOT EXISTS idx_definitionvotes_defid ON definitionvotes(definitionid);
CREATE INDEX IF NOT EXISTS idx_definitionvotes_userid_defid ON definitionvotes(userid, definitionid);

-- Supporting indexes for joins
CREATE INDEX IF NOT EXISTS idx_valsi_typeid ON valsi(typeid);
CREATE INDEX IF NOT EXISTS idx_definitions_langid ON definitions(langid);
CREATE INDEX IF NOT EXISTS idx_definitions_userid ON definitions(userid);
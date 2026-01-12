CREATE TABLE cached_dictionary_exports (
    id SERIAL PRIMARY KEY,
    language_tag TEXT NOT NULL,
    format TEXT NOT NULL,
    content BYTEA NOT NULL,
    content_type TEXT NOT NULL,
    filename TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(language_tag, format)
);

CREATE INDEX idx_cached_exports_lookup ON cached_dictionary_exports(language_tag, format);
CREATE INDEX idx_cached_exports_cleanup ON cached_dictionary_exports(created_at);
-- V1__initial_schema.sql
CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    message_id TEXT,
    date TEXT,
    subject TEXT,
    from_address TEXT,
    to_address TEXT,
    content TEXT,
    file_path TEXT
);

CREATE TABLE IF NOT EXISTS muplis (
    id SERIAL PRIMARY KEY,
    lojban TEXT,
    english TEXT
);

CREATE TABLE IF NOT EXISTS muplis_update (
    id SERIAL PRIMARY KEY,
    last_update BIGINT
);

CREATE TABLE IF NOT EXISTS dictionary (
    id SERIAL PRIMARY KEY,
    w TEXT NOT NULL,
    d TEXT,
    n TEXT,
    t TEXT,
    s TEXT,
    g TEXT,
    q TEXT,
    v TEXT,
    r TEXT,
    b TEXT
);

-- Create indexes for improved search performance
CREATE INDEX IF NOT EXISTS idx_messages_subject ON messages USING gin (subject gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_messages_content ON messages USING gin (content gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_muplis_lojban ON muplis USING gin (lojban gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_muplis_english ON muplis USING gin (english gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_dictionary_w ON dictionary USING gin (w gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_dictionary_d ON dictionary USING gin (d gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_messages_file_path ON messages(file_path);
ALTER TABLE messages ADD CONSTRAINT unique_message_id UNIQUE (message_id);

-- Enable the pg_trgm extension for better text search capabilities
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE collections (
    collection_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(userid),
    name TEXT NOT NULL,
    description TEXT,
    is_public BOOLEAN DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE collection_items (
    item_id SERIAL PRIMARY KEY,
    collection_id INTEGER NOT NULL REFERENCES collections(collection_id),
    definition_id INTEGER NOT NULL REFERENCES definitions(definitionid),
    notes TEXT,
    added_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(collection_id, definition_id)
);

CREATE INDEX idx_collections_user ON collections(user_id);
CREATE INDEX idx_collections_public ON collections(is_public);
CREATE INDEX idx_collection_items_collection ON collection_items(collection_id);
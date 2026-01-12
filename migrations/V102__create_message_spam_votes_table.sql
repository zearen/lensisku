CREATE TABLE public.message_spam_votes (
    message_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT message_spam_votes_pkey PRIMARY KEY (message_id, user_id),
    CONSTRAINT fk_message
        FOREIGN KEY(message_id)
        REFERENCES public.messages(id)
        ON DELETE CASCADE,
    CONSTRAINT fk_user
        FOREIGN KEY(user_id)
        REFERENCES public.users(userid)
        ON DELETE CASCADE
);

CREATE INDEX idx_message_spam_votes_message_id ON public.message_spam_votes(message_id);

-- Create payment related enums
CREATE TYPE payment_provider AS ENUM ('stripe', 'paypal', 'binance');
CREATE TYPE payment_status AS ENUM ('pending', 'succeeded', 'failed');

-- Create payments table
CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(userid),
    provider payment_provider NOT NULL,
    provider_payment_id TEXT NOT NULL,
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    currency TEXT NOT NULL,
    status payment_status NOT NULL DEFAULT 'pending',
    metadata JSONB,
    idempotency_key TEXT UNIQUE,
    error_message TEXT,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(provider, provider_payment_id)
);

-- Create user balances table
CREATE TABLE user_balances (
    user_id INTEGER PRIMARY KEY REFERENCES users(userid),
    balance_cents BIGINT NOT NULL DEFAULT 0 CHECK (balance_cents >= 0),
    total_spent_cents BIGINT NOT NULL DEFAULT 0,
    premium_expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create balance transactions table
CREATE TABLE balance_transactions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(userid),
    amount_cents BIGINT NOT NULL,
    currency TEXT NOT NULL,
    transaction_type TEXT NOT NULL,
    reference_id TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create payment audit log
CREATE TABLE payment_audit_log (
    id SERIAL PRIMARY KEY,
    payment_id INTEGER NOT NULL REFERENCES payments(id),
    user_id INTEGER NOT NULL REFERENCES users(userid),
    event_type TEXT NOT NULL,
    details TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_payments_user ON payments(user_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_idempotency ON payments(idempotency_key);
CREATE INDEX idx_payments_provider_id ON payments(provider, provider_payment_id);
CREATE INDEX idx_balance_transactions_user ON balance_transactions(user_id);
CREATE INDEX idx_payment_audit_payment ON payment_audit_log(payment_id);
CREATE INDEX idx_payment_audit_user ON payment_audit_log(user_id);
CREATE INDEX idx_balances_premium ON user_balances(premium_expires_at);

-- Function to process successful payment
CREATE OR REPLACE FUNCTION process_successful_payment(
    p_payment_id INTEGER,
    p_amount_cents BIGINT
) RETURNS void AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(p_payment_id);
    
    WITH payment_info AS (
        UPDATE payments 
        SET status = 'succeeded',
            completed_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_payment_id
        AND status = 'pending'
        RETURNING user_id
    )
    INSERT INTO balance_transactions (
        user_id, 
        amount_cents,
        currency,
        transaction_type,
        reference_id
    )
    SELECT 
        user_id,
        p_amount_cents,
        'USD',
        'payment_credit',
        p_payment_id::TEXT
    FROM payment_info;

    UPDATE user_balances
    SET balance_cents = balance_cents + p_amount_cents,
        total_spent_cents = total_spent_cents + p_amount_cents,
        updated_at = CURRENT_TIMESTAMP
    FROM payments
    WHERE payments.id = p_payment_id
    AND user_balances.user_id = payments.user_id;
END;
$$ LANGUAGE plpgsql;

-- Function to update premium status
CREATE OR REPLACE FUNCTION update_premium_status() RETURNS TRIGGER AS $$
BEGIN
    -- When balance increases, extend premium status
    IF NEW.balance_cents > OLD.balance_cents THEN
        NEW.premium_expires_at = GREATEST(
            COALESCE(NEW.premium_expires_at, NOW()),
            NOW() + INTERVAL '1 month'
        );
    END IF;
    
    -- When premium expires, reset balance
    IF NEW.premium_expires_at IS NOT NULL AND NEW.premium_expires_at < NOW() THEN
        NEW.balance_cents = 0;
        NEW.premium_expires_at = NULL;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to create initial user balance
CREATE OR REPLACE FUNCTION create_user_balance() 
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO user_balances (user_id, balance_cents, created_at, updated_at)
    VALUES (NEW.userid, 0, NOW(), NOW())
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER maintain_premium_status
    BEFORE UPDATE ON user_balances
    FOR EACH ROW
    EXECUTE FUNCTION update_premium_status();

CREATE TRIGGER ensure_user_balance
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION create_user_balance();
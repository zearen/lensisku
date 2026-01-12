-- Create a function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION public.trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the user_subscription_status ENUM type
CREATE TYPE public.user_subscription_status AS ENUM (
    'active',
    'inactive',
    'cancelled',
    'past_due',
    'pending_cancellation'
);

-- Add columns to the users table
ALTER TABLE public.users
ADD COLUMN subscription_status public.user_subscription_status NOT NULL DEFAULT 'inactive',
ADD COLUMN paypal_customer_id TEXT;

-- Create the paypal_subscriptions table
CREATE TABLE public.paypal_subscriptions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES public.users(userid) ON DELETE CASCADE,
    paypal_plan_id TEXT NOT NULL,
    paypal_subscription_id TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    next_billing_time TIMESTAMPTZ,
    last_payment_time TIMESTAMPTZ,
    last_payment_amount_cents BIGINT,
    last_payment_currency TEXT,
    cancel_reason TEXT,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes to the paypal_subscriptions table
CREATE INDEX idx_paypal_subscriptions_user_id ON public.paypal_subscriptions(user_id);
CREATE INDEX idx_paypal_subscriptions_paypal_subscription_id ON public.paypal_subscriptions(paypal_subscription_id);

-- Add trigger to update updated_at on paypal_subscriptions table
CREATE TRIGGER set_timestamp_paypal_subscriptions
BEFORE UPDATE ON public.paypal_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.trigger_set_timestamp();
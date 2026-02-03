-- ============================================================================
-- PAYMENT SYSTEM TABLES
-- Stripe Connect integration for escrow payments and helper payouts
-- ============================================================================

-- ============================================================================
-- STRIPE ACCOUNTS TABLE
-- Links helpers to their Stripe Connect accounts
-- ============================================================================
CREATE TABLE stripe_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    stripe_account_id TEXT NOT NULL,  -- acct_xxxxx
    onboarding_complete BOOLEAN DEFAULT FALSE,
    payouts_enabled BOOLEAN DEFAULT FALSE,
    charges_enabled BOOLEAN DEFAULT FALSE,
    details_submitted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT stripe_accounts_profile_unique UNIQUE (profile_id),
    CONSTRAINT stripe_accounts_stripe_id_unique UNIQUE (stripe_account_id)
);

CREATE INDEX idx_stripe_accounts_profile ON stripe_accounts(profile_id);

-- RLS for stripe_accounts
ALTER TABLE stripe_accounts ENABLE ROW LEVEL SECURITY;

-- Users can only view their own Stripe account
CREATE POLICY "Users can view own stripe account"
    ON stripe_accounts FOR SELECT
    USING (auth.uid() = profile_id);

-- Users can insert their own Stripe account (via edge function with service role)
CREATE POLICY "Service role can manage stripe accounts"
    ON stripe_accounts FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================================================
-- PAYMENT INTENTS TABLE
-- Tracks Stripe PaymentIntents for job payments
-- ============================================================================
CREATE TABLE payment_intents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    stripe_payment_intent_id TEXT NOT NULL,  -- pi_xxxxx
    amount_cents INTEGER NOT NULL,  -- Amount in cents (e.g., 5000 = €50.00)
    platform_fee_cents INTEGER NOT NULL,  -- Platform fee in cents (10%)
    currency TEXT NOT NULL DEFAULT 'eur',
    status TEXT NOT NULL DEFAULT 'requires_payment_method',
    -- Stripe PaymentIntent statuses:
    -- requires_payment_method, requires_confirmation, requires_action,
    -- processing, requires_capture, canceled, succeeded
    client_secret TEXT,  -- For frontend to confirm payment
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT payment_intents_stripe_id_unique UNIQUE (stripe_payment_intent_id)
);

CREATE INDEX idx_payment_intents_job ON payment_intents(job_id);
CREATE INDEX idx_payment_intents_status ON payment_intents(status);

-- RLS for payment_intents
ALTER TABLE payment_intents ENABLE ROW LEVEL SECURITY;

-- Job poster can view payment intents for their jobs
CREATE POLICY "Job poster can view payment intents"
    ON payment_intents FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM jobs
            WHERE jobs.id = payment_intents.job_id
            AND jobs.poster_id = auth.uid()
        )
    );

-- Assigned helper can view payment intents for their jobs
CREATE POLICY "Assigned helper can view payment intents"
    ON payment_intents FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM jobs
            WHERE jobs.id = payment_intents.job_id
            AND jobs.assigned_to = auth.uid()
        )
    );

-- ============================================================================
-- WITHDRAWALS TABLE
-- Tracks helper withdrawal/payout requests
-- ============================================================================
CREATE TABLE withdrawals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    stripe_payout_id TEXT,  -- po_xxxxx (null until processed)
    amount_cents INTEGER NOT NULL,  -- Amount in cents
    currency TEXT NOT NULL DEFAULT 'eur',
    status TEXT NOT NULL DEFAULT 'pending',
    -- Withdrawal statuses:
    -- pending (requested), processing (sent to Stripe),
    -- paid (arrived at bank), failed (rejected), canceled
    destination_iban_last4 TEXT,  -- Last 4 digits for display
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    failure_code TEXT,
    failure_message TEXT,

    CONSTRAINT withdrawals_min_amount CHECK (amount_cents >= 500)  -- Minimum €5
);

CREATE INDEX idx_withdrawals_profile ON withdrawals(profile_id);
CREATE INDEX idx_withdrawals_status ON withdrawals(status);

-- RLS for withdrawals
ALTER TABLE withdrawals ENABLE ROW LEVEL SECURITY;

-- Users can only view their own withdrawals
CREATE POLICY "Users can view own withdrawals"
    ON withdrawals FOR SELECT
    USING (auth.uid() = profile_id);

-- Users can insert their own withdrawals
CREATE POLICY "Users can create own withdrawals"
    ON withdrawals FOR INSERT
    WITH CHECK (auth.uid() = profile_id);

-- ============================================================================
-- ADD PAYMENT COLUMNS TO JOBS TABLE
-- ============================================================================
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid';
-- Payment statuses: unpaid, paid (in escrow), released, refunded

ALTER TABLE jobs ADD COLUMN IF NOT EXISTS dispute_window_ends_at TIMESTAMPTZ;
-- When the 7-day dispute window ends (set when job marked complete)

ALTER TABLE jobs ADD COLUMN IF NOT EXISTS payment_released_at TIMESTAMPTZ;
-- When funds were released to helper

-- Add constraint for valid payment statuses
ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_payment_status_check;
ALTER TABLE jobs ADD CONSTRAINT jobs_payment_status_check
    CHECK (payment_status IN ('unpaid', 'paid', 'released', 'refunded'));

-- Index for payment status queries
CREATE INDEX IF NOT EXISTS idx_jobs_payment_status ON jobs(payment_status);

-- ============================================================================
-- ADD COLUMNS TO TRANSACTIONS TABLE
-- Link transactions to Stripe entities
-- ============================================================================
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS stripe_payment_intent_id TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS stripe_transfer_id TEXT;
-- tr_xxxxx (transfer to helper's Connect account)

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS platform_fee_amount DECIMAL(10, 2);
-- Platform fee taken from this transaction

-- ============================================================================
-- HELPER BALANCE VIEW
-- Calculates available and pending balance for helpers
-- ============================================================================
CREATE OR REPLACE VIEW helper_balances AS
SELECT
    p.id AS profile_id,
    -- Released funds (available to withdraw)
    COALESCE(
        SUM(
            CASE WHEN t.status = 'released' THEN t.amount ELSE 0 END
        ), 0
    ) - COALESCE(
        (SELECT SUM(w.amount_cents::DECIMAL / 100)
         FROM withdrawals w
         WHERE w.profile_id = p.id
         AND w.status IN ('processing', 'paid')),
        0
    ) AS available_balance,
    -- Held funds (in dispute window)
    COALESCE(
        SUM(
            CASE WHEN t.status = 'held' THEN t.amount ELSE 0 END
        ), 0
    ) AS pending_balance,
    -- Total earned all time
    COALESCE(
        SUM(
            CASE WHEN t.status IN ('released', 'held') THEN t.amount ELSE 0 END
        ), 0
    ) AS total_earned,
    -- This year's earnings (for tax tracking)
    COALESCE(
        SUM(
            CASE
                WHEN t.status = 'released'
                AND EXTRACT(YEAR FROM t.released_at) = EXTRACT(YEAR FROM CURRENT_DATE)
                THEN t.amount
                ELSE 0
            END
        ), 0
    ) AS ytd_earnings,
    -- This year's transaction count
    COUNT(
        CASE
            WHEN t.status = 'released'
            AND EXTRACT(YEAR FROM t.released_at) = EXTRACT(YEAR FROM CURRENT_DATE)
            THEN 1
        END
    ) AS ytd_transaction_count
FROM profiles p
LEFT JOIN jobs j ON j.assigned_to = p.id
LEFT JOIN transactions t ON t.job_id = j.id
WHERE p.user_type = 'helper'
GROUP BY p.id;

-- ============================================================================
-- FUNCTION: Update timestamps
-- ============================================================================
CREATE OR REPLACE FUNCTION update_payment_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER stripe_accounts_updated_at
    BEFORE UPDATE ON stripe_accounts
    FOR EACH ROW
    EXECUTE FUNCTION update_payment_updated_at();

CREATE TRIGGER payment_intents_updated_at
    BEFORE UPDATE ON payment_intents
    FOR EACH ROW
    EXECUTE FUNCTION update_payment_updated_at();

-- ============================================================================
-- FUNCTION: Check if helper needs to provide KYC info before withdrawal
-- ============================================================================
CREATE OR REPLACE FUNCTION check_helper_kyc_complete(helper_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    profile_record RECORD;
BEGIN
    SELECT dni_nie, iban, address_street, address_city, address_postal_code
    INTO profile_record
    FROM profiles
    WHERE id = helper_id;

    RETURN (
        profile_record.dni_nie IS NOT NULL AND
        profile_record.iban IS NOT NULL AND
        profile_record.address_street IS NOT NULL AND
        profile_record.address_city IS NOT NULL AND
        profile_record.address_postal_code IS NOT NULL
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

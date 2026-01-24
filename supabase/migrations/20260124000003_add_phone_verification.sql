-- Add phone_verified field to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone_verified BOOLEAN DEFAULT FALSE;

-- Create verification_codes table
CREATE TABLE IF NOT EXISTS verification_codes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    phone TEXT NOT NULL,
    code TEXT NOT NULL,
    attempts INTEGER DEFAULT 0,
    expires_at TIMESTAMPTZ NOT NULL,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for quick lookup
CREATE INDEX IF NOT EXISTS idx_verification_codes_user_phone
ON verification_codes(user_id, phone, verified)
WHERE verified = FALSE;

-- RLS policies for verification_codes
ALTER TABLE verification_codes ENABLE ROW LEVEL SECURITY;

-- Users can only see their own verification codes
CREATE POLICY "Users can view own verification codes"
ON verification_codes FOR SELECT
USING (auth.uid() = user_id);

-- Users can insert their own verification codes
CREATE POLICY "Users can create own verification codes"
ON verification_codes FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own verification codes (for attempt tracking)
CREATE POLICY "Users can update own verification codes"
ON verification_codes FOR UPDATE
USING (auth.uid() = user_id);

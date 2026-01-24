-- Add additional profile fields for tax compliance, payments, and convenience
-- All fields are optional (NULL) to not block signups

-- Contact information
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone TEXT;

-- Tax compliance fields (for helpers)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS dni_nie TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS address_street TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS address_city TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS address_postal_code TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS address_country TEXT DEFAULT 'ES';

-- Payment information
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS iban TEXT; -- For helpers to receive money
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS payment_provider_customer_id TEXT; -- Stripe/Mangopay customer ID

-- Convenience fields (optional defaults)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS default_location_address TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS default_barrio TEXT;

-- Profile completion tracking
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS tax_info_completed BOOLEAN DEFAULT false; -- For helpers only

-- Account status
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS account_status TEXT DEFAULT 'active'
  CHECK (account_status IN ('active', 'suspended', 'pending_verification', 'deleted'));

-- Verification timestamps
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS identity_verified_at TIMESTAMPTZ; -- When DNI/NIE verified

-- Tax reporting tracking (for helpers)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS annual_earnings_eur DECIMAL(10, 2) DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS transaction_count INTEGER DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS tax_reporting_required BOOLEAN DEFAULT false;

-- Add indexes for common queries
CREATE INDEX IF NOT EXISTS idx_profiles_phone ON profiles(phone);
CREATE INDEX IF NOT EXISTS idx_profiles_dni_nie ON profiles(dni_nie);
CREATE INDEX IF NOT EXISTS idx_profiles_account_status ON profiles(account_status);
CREATE INDEX IF NOT EXISTS idx_profiles_tax_reporting ON profiles(tax_reporting_required) WHERE tax_reporting_required = true;

-- Update RLS policies to allow users to update their own extended profile
-- (Existing policies already allow this, but let's be explicit)

-- Comments for documentation
COMMENT ON COLUMN profiles.dni_nie IS 'Spanish tax ID (DNI for citizens, NIE for foreigners). Required for helpers earning €2000+/year or 30+ transactions.';
COMMENT ON COLUMN profiles.iban IS 'Bank account for receiving payments. Required for helpers to withdraw earnings.';
COMMENT ON COLUMN profiles.phone IS 'Contact phone number. Collected when user first applies to a job or posts a job.';
COMMENT ON COLUMN profiles.tax_reporting_required IS 'Auto-set to true when helper reaches €2000 annual earnings or 30 transactions (Modelo 238 threshold).';
COMMENT ON COLUMN profiles.annual_earnings_eur IS 'Running total of earnings in current tax year. Reset annually. Used for DAC7 compliance.';
COMMENT ON COLUMN profiles.payment_provider_customer_id IS 'External payment provider customer ID (Stripe/Mangopay).';

-- Function to check and update tax reporting requirement (called after each transaction)
CREATE OR REPLACE FUNCTION check_tax_reporting_requirement()
RETURNS TRIGGER AS $$
BEGIN
  -- Only for helpers
  IF (SELECT user_type FROM profiles WHERE id = NEW.id) = 'helper' THEN
    -- Check if threshold met
    IF NEW.annual_earnings_eur >= 2000 OR NEW.transaction_count >= 30 THEN
      NEW.tax_reporting_required := true;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update tax reporting flag
DROP TRIGGER IF EXISTS trigger_check_tax_reporting ON profiles;
CREATE TRIGGER trigger_check_tax_reporting
  BEFORE UPDATE OF annual_earnings_eur, transaction_count ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION check_tax_reporting_requirement();

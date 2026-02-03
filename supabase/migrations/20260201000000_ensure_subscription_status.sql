-- Ensure all profiles have subscription_status set
-- (should already be 'free_trial' from the default, but be safe)
UPDATE profiles
SET subscription_status = 'free_trial'
WHERE subscription_status IS NULL;

-- Clarify that this field is used for both helpers and seekers
COMMENT ON COLUMN profiles.subscription_status IS
  'Subscription tier for premium features (SMS/WhatsApp/email notifications). Used for both helpers and seekers. free_trial and active = premium enabled.';

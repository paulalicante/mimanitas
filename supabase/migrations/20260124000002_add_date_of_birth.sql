-- Add date of birth field to profiles
-- This allows age display, birthday greetings, and special offers

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS date_of_birth DATE;

-- Index for efficient birthday queries (to find upcoming birthdays)
-- Extract month and day for birthday matching regardless of year
CREATE INDEX IF NOT EXISTS idx_profiles_birthday
  ON profiles (EXTRACT(MONTH FROM date_of_birth), EXTRACT(DAY FROM date_of_birth));

-- Comment for documentation
COMMENT ON COLUMN profiles.date_of_birth IS 'User date of birth. Used for age display and birthday greetings/offers. Optional field.';

-- Function to calculate age from date of birth
CREATE OR REPLACE FUNCTION calculate_age(dob DATE)
RETURNS INTEGER AS $$
BEGIN
  IF dob IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN DATE_PART('year', AGE(dob));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to get users with birthdays today
CREATE OR REPLACE FUNCTION get_todays_birthdays()
RETURNS TABLE (
  user_id UUID,
  name TEXT,
  email TEXT,
  age INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    id,
    profiles.name,
    profiles.email,
    calculate_age(date_of_birth)
  FROM profiles
  WHERE EXTRACT(MONTH FROM date_of_birth) = EXTRACT(MONTH FROM CURRENT_DATE)
    AND EXTRACT(DAY FROM date_of_birth) = EXTRACT(DAY FROM CURRENT_DATE)
    AND account_status = 'active';
END;
$$ LANGUAGE plpgsql;

-- Function to get users with birthdays in next N days
CREATE OR REPLACE FUNCTION get_upcoming_birthdays(days_ahead INTEGER DEFAULT 7)
RETURNS TABLE (
  user_id UUID,
  name TEXT,
  email TEXT,
  date_of_birth DATE,
  age INTEGER,
  days_until_birthday INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    id,
    profiles.name,
    profiles.email,
    profiles.date_of_birth,
    calculate_age(profiles.date_of_birth),
    EXTRACT(DAY FROM (
      DATE_TRUNC('year', CURRENT_DATE) +
      (EXTRACT(MONTH FROM profiles.date_of_birth) - 1) * INTERVAL '1 month' +
      (EXTRACT(DAY FROM profiles.date_of_birth) - 1) * INTERVAL '1 day' -
      CURRENT_DATE
    ))::INTEGER AS days_until
  FROM profiles
  WHERE profiles.date_of_birth IS NOT NULL
    AND account_status = 'active'
    AND EXTRACT(DAY FROM (
      DATE_TRUNC('year', CURRENT_DATE) +
      (EXTRACT(MONTH FROM profiles.date_of_birth) - 1) * INTERVAL '1 month' +
      (EXTRACT(DAY FROM profiles.date_of_birth) - 1) * INTERVAL '1 day' -
      CURRENT_DATE
    )) BETWEEN 0 AND days_ahead
  ORDER BY days_until;
END;
$$ LANGUAGE plpgsql;

-- Smart matching: add travel preferences and flexible scheduling
-- Extends notification_preferences with transport/travel columns
-- Extends jobs with flexible scheduling flag

-- Transport modes and max travel time for helpers
ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS transport_modes TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS max_travel_minutes INTEGER DEFAULT 30;

COMMENT ON COLUMN notification_preferences.transport_modes IS 'Transport modes: car, bike, walk, transit, escooter. Empty = no distance filtering.';
COMMENT ON COLUMN notification_preferences.max_travel_minutes IS 'Max travel time in minutes helper will travel. Default 30.';

-- Flexible scheduling for jobs
ALTER TABLE jobs
  ADD COLUMN IF NOT EXISTS is_flexible BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS estimated_duration_minutes INTEGER;

COMMENT ON COLUMN jobs.is_flexible IS 'If true, seeker has no fixed date/time preference.';
COMMENT ON COLUMN jobs.estimated_duration_minutes IS 'Estimated job duration in minutes.';

-- Better index for availability queries (used in matching)
CREATE INDEX IF NOT EXISTS idx_availability_user_dow_date
  ON availability(user_id, day_of_week, specific_date);

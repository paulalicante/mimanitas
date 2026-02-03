-- Add min_hourly_rate column to notification_preferences
-- so helpers can set separate minimums for fixed-price jobs vs hourly jobs.

ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS min_hourly_rate DECIMAL(10, 2);

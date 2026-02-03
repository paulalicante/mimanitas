-- Add paused flag to notification_preferences
-- When true, helper receives no external or in-app job notifications
ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT false;

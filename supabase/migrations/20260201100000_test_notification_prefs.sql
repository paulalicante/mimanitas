-- Insert notification preferences for helper account (Paul Spain) for testing
-- WhatsApp + SMS enabled, no skill/barrio filters
INSERT INTO notification_preferences (user_id, in_app_enabled, sound_enabled, sms_enabled, whatsapp_enabled, email_enabled, notify_skills, notify_barrios)
VALUES ('2839c0fe-334d-4e23-a476-39b73163cac5', true, true, true, true, false, '{}', '{}')
ON CONFLICT (user_id) DO UPDATE SET
  sms_enabled = true,
  whatsapp_enabled = true;

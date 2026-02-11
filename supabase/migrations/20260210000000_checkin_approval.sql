-- Add check-in approval field for seeker confirmation
ALTER TABLE jobs
ADD COLUMN IF NOT EXISTS checkin_approved_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS checkin_approved_by UUID REFERENCES profiles(id);

COMMENT ON COLUMN jobs.checkin_approved_at IS 'When seeker approved helper arrival';
COMMENT ON COLUMN jobs.checkin_approved_by IS 'Seeker who approved the check-in';

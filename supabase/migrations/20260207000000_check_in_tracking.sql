-- Check-in tracking for mobile app
-- Allows helpers to check in/out of jobs with GPS verification

-- Add check-in columns to jobs table
ALTER TABLE jobs
ADD COLUMN IF NOT EXISTS checked_in_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS checked_out_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS check_in_lat DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS check_in_lng DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS check_out_lat DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS check_out_lng DOUBLE PRECISION;

-- Index for finding jobs that need check-in (assigned jobs on today's date)
CREATE INDEX IF NOT EXISTS idx_jobs_checkin_pending
ON jobs (scheduled_date, status)
WHERE status = 'assigned' AND checked_in_at IS NULL;

-- Comment explaining the columns
COMMENT ON COLUMN jobs.checked_in_at IS 'When the helper checked in to start the job (mobile app only)';
COMMENT ON COLUMN jobs.checked_out_at IS 'When the helper checked out after completing the job (mobile app only)';
COMMENT ON COLUMN jobs.check_in_lat IS 'GPS latitude at check-in time';
COMMENT ON COLUMN jobs.check_in_lng IS 'GPS longitude at check-in time';
COMMENT ON COLUMN jobs.check_out_lat IS 'GPS latitude at check-out time';
COMMENT ON COLUMN jobs.check_out_lng IS 'GPS longitude at check-out time';

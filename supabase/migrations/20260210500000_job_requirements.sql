-- Add job_requirements JSONB column to store seeker's specific requirements
-- Example: {"cleaning_types": ["deep"], "includes_free": ["windows", "oven"]}
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS job_requirements JSONB DEFAULT '{}';

-- Index for faster filtering
CREATE INDEX IF NOT EXISTS idx_jobs_requirements ON jobs USING GIN (job_requirements);

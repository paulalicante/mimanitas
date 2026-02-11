-- Add checkout approval fields for seeker confirmation of job completion
ALTER TABLE jobs
ADD COLUMN IF NOT EXISTS checkout_approved_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS checkout_approved_by UUID REFERENCES profiles(id);

COMMENT ON COLUMN jobs.checkout_approved_at IS 'When seeker approved job completion and released payment';
COMMENT ON COLUMN jobs.checkout_approved_by IS 'Seeker who approved the checkout';

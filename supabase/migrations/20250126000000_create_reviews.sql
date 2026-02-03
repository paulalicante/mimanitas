-- Create reviews table if not exists
CREATE TABLE IF NOT EXISTS reviews (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  reviewer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reviewee_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  rating DECIMAL(2,1) NOT NULL CHECK (rating >= 0.5 AND rating <= 5.0 AND (rating * 10) % 5 = 0),
  comment TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  -- Ensure each person can only review once per job
  UNIQUE(job_id, reviewer_id)
);

-- Add rating fields to profiles
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS average_rating DECIMAL(3,2) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS review_count INTEGER DEFAULT 0;

-- Create indexes if not exist
CREATE INDEX IF NOT EXISTS idx_reviews_reviewee ON reviews(reviewee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reviews_job ON reviews(job_id);

-- Enable RLS
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Anyone can read reviews" ON reviews;
DROP POLICY IF EXISTS "Users can create reviews for their jobs" ON reviews;

-- Allow users to read all reviews
CREATE POLICY "Anyone can read reviews"
  ON reviews FOR SELECT
  USING (true);

-- Allow users to create reviews for jobs they're involved in
CREATE POLICY "Users can create reviews for their jobs"
  ON reviews FOR INSERT
  WITH CHECK (
    auth.uid() = reviewer_id
    AND EXISTS (
      SELECT 1 FROM jobs j
      LEFT JOIN applications a ON a.job_id = j.id
      WHERE j.id = job_id
      AND j.status = 'completed'
      AND (
        (j.poster_id = auth.uid() AND a.applicant_id = reviewee_id AND a.status = 'accepted')
        OR (a.applicant_id = auth.uid() AND a.status = 'accepted' AND j.poster_id = reviewee_id)
      )
    )
  );

-- Function to update average rating
CREATE OR REPLACE FUNCTION update_average_rating()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE profiles
    SET
      review_count = review_count + 1,
      average_rating = (
        SELECT AVG(rating)::DECIMAL(3,2)
        FROM reviews
        WHERE reviewee_id = NEW.reviewee_id
      )
    WHERE id = NEW.reviewee_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE profiles
    SET
      review_count = GREATEST(review_count - 1, 0),
      average_rating = (
        SELECT AVG(rating)::DECIMAL(3,2)
        FROM reviews
        WHERE reviewee_id = OLD.reviewee_id
      )
    WHERE id = OLD.reviewee_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS update_profile_rating ON reviews;

-- Trigger to automatically update average rating
CREATE TRIGGER update_profile_rating
AFTER INSERT OR DELETE ON reviews
FOR EACH ROW
EXECUTE FUNCTION update_average_rating();

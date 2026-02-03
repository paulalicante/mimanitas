-- Recalculate all profile ratings based on existing reviews
UPDATE profiles
SET
  review_count = COALESCE((
    SELECT COUNT(*)
    FROM reviews
    WHERE reviewee_id = profiles.id
  ), 0),
  average_rating = (
    SELECT AVG(rating)::DECIMAL(3,2)
    FROM reviews
    WHERE reviewee_id = profiles.id
  );

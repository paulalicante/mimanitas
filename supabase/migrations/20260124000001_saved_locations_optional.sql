-- OPTIONAL FEATURE: Saved Locations
-- This allows seekers to save frequently-used job locations
-- Can be implemented in Phase 2 after MVP is working

-- Uncomment to enable this feature:

/*
CREATE TABLE saved_locations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  label TEXT NOT NULL, -- e.g., "Mi casa", "Casa de mis padres", "Piso de alquiler"
  address TEXT NOT NULL,
  barrio TEXT,
  location_lat DECIMAL(10, 8),
  location_lng DECIMAL(11, 8),
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure only one default location per user
CREATE UNIQUE INDEX idx_saved_locations_default
  ON saved_locations(user_id)
  WHERE is_default = true;

CREATE INDEX idx_saved_locations_user ON saved_locations(user_id);

-- RLS policies
ALTER TABLE saved_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own saved locations"
  ON saved_locations FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own saved locations"
  ON saved_locations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own saved locations"
  ON saved_locations FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own saved locations"
  ON saved_locations FOR DELETE
  USING (auth.uid() = user_id);

-- Trigger for updated_at
CREATE TRIGGER set_updated_at_saved_locations
  BEFORE UPDATE ON saved_locations
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

-- Function to ensure only one default location
CREATE OR REPLACE FUNCTION ensure_single_default_location()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_default = true THEN
    -- Unset all other defaults for this user
    UPDATE saved_locations
    SET is_default = false
    WHERE user_id = NEW.user_id
      AND id != NEW.id
      AND is_default = true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ensure_single_default
  BEFORE INSERT OR UPDATE ON saved_locations
  FOR EACH ROW
  WHEN (NEW.is_default = true)
  EXECUTE FUNCTION ensure_single_default_location();
*/

-- Note: This table is commented out for now
-- To enable: Uncomment the entire block above and run migration

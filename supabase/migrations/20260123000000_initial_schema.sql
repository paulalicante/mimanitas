-- Mi Manitas Initial Database Schema
-- This migration creates all core tables for the platform

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- PROFILES TABLE
-- Extends Supabase auth.users with additional user information
-- IMPORTANT: Users must choose ONE role (helper OR seeker), not both
-- This enforces the business model: seekers pay subscription, helpers are free
-- ============================================================================
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  name TEXT NOT NULL,
  bio TEXT,
  location_lat DECIMAL(10, 8),
  location_lng DECIMAL(11, 8),
  barrio TEXT,
  user_type TEXT NOT NULL CHECK (user_type IN ('helper', 'seeker')),
  phone TEXT,
  avatar_url TEXT,

  -- Subscription fields (only for seekers)
  subscription_status TEXT CHECK (subscription_status IN ('free_trial', 'active', 'cancelled', 'expired')) DEFAULT 'free_trial',
  subscription_started_at TIMESTAMPTZ,
  subscription_expires_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for location-based queries
CREATE INDEX idx_profiles_location ON profiles(location_lat, location_lng);
CREATE INDEX idx_profiles_barrio ON profiles(barrio);
CREATE INDEX idx_profiles_user_type ON profiles(user_type);
CREATE INDEX idx_profiles_subscription_status ON profiles(subscription_status);

-- RLS Policies for profiles
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Anyone can view profiles
CREATE POLICY "Profiles are viewable by everyone"
  ON profiles FOR SELECT
  USING (true);

-- Users can insert their own profile
CREATE POLICY "Users can insert their own profile"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update their own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);

-- ============================================================================
-- SKILLS TABLE
-- Predefined list of skills/services offered on the platform
-- ============================================================================
CREATE TABLE skills (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL UNIQUE,
  name_es TEXT NOT NULL UNIQUE, -- Spanish translation
  description TEXT,
  icon TEXT, -- Emoji or icon identifier
  category TEXT, -- e.g., 'limpieza', 'jardinería', 'mudanza'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insert common skills
INSERT INTO skills (name, name_es, icon, category) VALUES
  ('painting', 'Pintura', '🎨', 'mantenimiento'),
  ('gardening', 'Jardinería', '🌱', 'jardinería'),
  ('cleaning', 'Limpieza', '🧹', 'limpieza'),
  ('moving', 'Mudanza', '📦', 'mudanza'),
  ('furniture_assembly', 'Montaje de muebles', '🔧', 'mantenimiento'),
  ('plumbing', 'Fontanería', '🚰', 'profesional'),
  ('electrical', 'Electricidad', '⚡', 'profesional'),
  ('pet_care', 'Cuidado de mascotas', '🐕', 'cuidados'),
  ('childcare', 'Cuidado de niños', '👶', 'cuidados'),
  ('cooking', 'Cocina', '👨‍🍳', 'hogar'),
  ('shopping', 'Compras', '🛒', 'hogar'),
  ('tech_help', 'Ayuda técnica', '💻', 'tecnología'),
  ('tutoring', 'Clases particulares', '📚', 'educación'),
  ('translation', 'Traducción', '🌍', 'servicios');

-- RLS for skills (read-only for all users)
ALTER TABLE skills ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Skills are viewable by everyone"
  ON skills FOR SELECT
  USING (true);

-- ============================================================================
-- USER_SKILLS TABLE
-- Junction table connecting users to their skills
-- ============================================================================
CREATE TABLE user_skills (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  skill_id UUID NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
  experience_years INTEGER,
  rate_per_hour DECIMAL(10, 2), -- Optional hourly rate
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, skill_id)
);

CREATE INDEX idx_user_skills_user ON user_skills(user_id);
CREATE INDEX idx_user_skills_skill ON user_skills(skill_id);

-- RLS for user_skills
ALTER TABLE user_skills ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User skills are viewable by everyone"
  ON user_skills FOR SELECT
  USING (true);

CREATE POLICY "Users can manage their own skills"
  ON user_skills FOR ALL
  USING (auth.uid() = user_id);

-- ============================================================================
-- AVAILABILITY TABLE
-- When helpers are available to work
-- ============================================================================
CREATE TABLE availability (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Sunday, 6=Saturday
  specific_date DATE, -- For one-off availability
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  is_recurring BOOLEAN NOT NULL DEFAULT false,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (
    (is_recurring = true AND day_of_week IS NOT NULL AND specific_date IS NULL) OR
    (is_recurring = false AND specific_date IS NOT NULL)
  )
);

CREATE INDEX idx_availability_user ON availability(user_id);
CREATE INDEX idx_availability_date ON availability(specific_date);
CREATE INDEX idx_availability_dow ON availability(day_of_week);

-- RLS for availability
ALTER TABLE availability ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Availability is viewable by everyone"
  ON availability FOR SELECT
  USING (true);

CREATE POLICY "Only helpers can manage their availability"
  ON availability FOR ALL
  USING (
    auth.uid() = user_id AND
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND user_type = 'helper')
  );

-- ============================================================================
-- JOBS TABLE
-- Posted needs/requests for help
-- ============================================================================
CREATE TABLE jobs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  poster_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  skill_id UUID REFERENCES skills(id),
  location_lat DECIMAL(10, 8),
  location_lng DECIMAL(11, 8),
  location_address TEXT,
  barrio TEXT,
  price_type TEXT NOT NULL CHECK (price_type IN ('fixed', 'hourly')),
  price_amount DECIMAL(10, 2) NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('open', 'assigned', 'in_progress', 'completed', 'disputed', 'cancelled')) DEFAULT 'open',
  scheduled_date DATE,
  scheduled_time TIME,
  pickup_offered BOOLEAN DEFAULT false, -- Can worker pick up the poster?
  assigned_to UUID REFERENCES profiles(id), -- Who got the job
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_jobs_poster ON jobs(poster_id);
CREATE INDEX idx_jobs_skill ON jobs(skill_id);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_location ON jobs(location_lat, location_lng);
CREATE INDEX idx_jobs_barrio ON jobs(barrio);
CREATE INDEX idx_jobs_assigned ON jobs(assigned_to);

-- RLS for jobs
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Jobs are viewable by everyone"
  ON jobs FOR SELECT
  USING (true);

CREATE POLICY "Only seekers can create jobs"
  ON jobs FOR INSERT
  WITH CHECK (
    auth.uid() = poster_id AND
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND user_type = 'seeker')
  );

CREATE POLICY "Job posters can update their jobs"
  ON jobs FOR UPDATE
  USING (auth.uid() = poster_id);

CREATE POLICY "Assigned workers can update job status"
  ON jobs FOR UPDATE
  USING (auth.uid() = assigned_to);

-- ============================================================================
-- APPLICATIONS TABLE
-- When helpers apply to jobs
-- ============================================================================
CREATE TABLE applications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  applicant_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  message TEXT,
  proposed_rate DECIMAL(10, 2), -- If negotiating
  can_pickup BOOLEAN DEFAULT false, -- Can applicant pick up the poster?
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'rejected', 'withdrawn')) DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(job_id, applicant_id)
);

CREATE INDEX idx_applications_job ON applications(job_id);
CREATE INDEX idx_applications_applicant ON applications(applicant_id);
CREATE INDEX idx_applications_status ON applications(status);

-- RLS for applications
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Applications viewable by poster and applicant"
  ON applications FOR SELECT
  USING (
    auth.uid() IN (
      SELECT poster_id FROM jobs WHERE id = job_id
      UNION
      SELECT applicant_id
    )
  );

CREATE POLICY "Only helpers can create applications"
  ON applications FOR INSERT
  WITH CHECK (
    auth.uid() = applicant_id AND
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND user_type = 'helper')
  );

CREATE POLICY "Applicants can update their applications"
  ON applications FOR UPDATE
  USING (auth.uid() = applicant_id);

CREATE POLICY "Job posters can update application status"
  ON applications FOR UPDATE
  USING (
    auth.uid() IN (SELECT poster_id FROM jobs WHERE id = job_id)
  );

-- ============================================================================
-- MESSAGES TABLE
-- Direct messages between users
-- ============================================================================
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  job_id UUID REFERENCES jobs(id) ON DELETE SET NULL, -- Optional context
  content TEXT NOT NULL,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_receiver ON messages(receiver_id);
CREATE INDEX idx_messages_job ON messages(job_id);
CREATE INDEX idx_messages_created ON messages(created_at DESC);

-- RLS for messages
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their messages"
  ON messages FOR SELECT
  USING (auth.uid() IN (sender_id, receiver_id));

CREATE POLICY "Users can send messages"
  ON messages FOR INSERT
  WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Receivers can update read status"
  ON messages FOR UPDATE
  USING (auth.uid() = receiver_id);

-- ============================================================================
-- REVIEWS TABLE
-- Ratings and reviews after job completion
-- Note: Only for non-disputed transactions per claude.md
-- ============================================================================
CREATE TABLE reviews (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reviewer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reviewee_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(reviewer_id, job_id) -- One review per person per job
);

CREATE INDEX idx_reviews_reviewee ON reviews(reviewee_id);
CREATE INDEX idx_reviews_job ON reviews(job_id);

-- RLS for reviews
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Reviews are viewable by everyone"
  ON reviews FOR SELECT
  USING (true);

CREATE POLICY "Users involved in job can create review"
  ON reviews FOR INSERT
  WITH CHECK (
    auth.uid() = reviewer_id AND
    EXISTS (
      SELECT 1 FROM jobs
      WHERE id = job_id
      AND status = 'completed'
      AND (poster_id = auth.uid() OR assigned_to = auth.uid())
    )
  );

-- ============================================================================
-- TRANSACTIONS TABLE
-- Escrow payment tracking
-- ============================================================================
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  amount DECIMAL(10, 2) NOT NULL,
  currency TEXT NOT NULL DEFAULT 'EUR',
  status TEXT NOT NULL CHECK (status IN ('pending', 'held', 'released', 'disputed', 'split', 'refunded')) DEFAULT 'pending',
  payment_provider TEXT, -- 'mangopay' or 'stripe'
  provider_transaction_id TEXT, -- External payment ID
  held_at TIMESTAMPTZ,
  released_at TIMESTAMPTZ,
  disputed_at TIMESTAMPTZ,
  dispute_resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transactions_job ON transactions(job_id);
CREATE INDEX idx_transactions_status ON transactions(status);

-- RLS for transactions
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Transaction participants can view"
  ON transactions FOR SELECT
  USING (
    auth.uid() IN (
      SELECT poster_id FROM jobs WHERE id = job_id
      UNION
      SELECT assigned_to FROM jobs WHERE id = job_id
    )
  );

-- ============================================================================
-- FUNCTIONS AND TRIGGERS
-- ============================================================================

-- Function to create profile on signup
-- Expects user_type to be passed in raw_user_meta_data during signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name, user_type)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'user_type', 'helper') -- Default to helper if not specified
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to auto-create profile
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER set_updated_at_profiles
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER set_updated_at_jobs
  BEFORE UPDATE ON jobs
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER set_updated_at_applications
  BEFORE UPDATE ON applications
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER set_updated_at_transactions
  BEFORE UPDATE ON transactions
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View for user ratings summary
CREATE VIEW user_ratings AS
SELECT
  reviewee_id as user_id,
  COUNT(*) as total_reviews,
  AVG(rating) as average_rating,
  COUNT(CASE WHEN rating = 5 THEN 1 END) as five_star_count,
  COUNT(CASE WHEN rating = 4 THEN 1 END) as four_star_count,
  COUNT(CASE WHEN rating = 3 THEN 1 END) as three_star_count,
  COUNT(CASE WHEN rating = 2 THEN 1 END) as two_star_count,
  COUNT(CASE WHEN rating = 1 THEN 1 END) as one_star_count
FROM reviews
GROUP BY reviewee_id;

-- Make view readable by everyone
GRANT SELECT ON user_ratings TO authenticated, anon;

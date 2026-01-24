# Mi Manitas Database Schema

## Overview

This directory contains SQL migrations for the Mi Manitas platform database.

## Critical Business Rule: Separate User Types

**Users must choose ONE role when signing up:**
- **Helper** (Manitas) - Free forever. Can post availability and apply to jobs.
- **Seeker** (Employer) - Pays subscription (€10/month after free trial). Can post jobs.

This separation is enforced at the database level to support the business model. If someone wants to be both, they would need to create separate accounts (though this is not the expected use case).

## Schema Structure

### Core Tables

1. **profiles** - Extends Supabase auth.users with user information
   - Name, bio, location, user type (helper OR seeker - must choose one)
   - Subscription tracking for seekers (status, started_at, expires_at)
   - Auto-created when user signs up via trigger (but user_type must be set during signup)
   - Viewable by everyone, editable by owner

2. **skills** - Predefined list of services
   - Spanish names and categories
   - 14 initial skills (painting, gardening, cleaning, etc.)
   - Read-only for all users

3. **user_skills** - Junction table for user → skills
   - Links users to their skills
   - Optional hourly rate and experience
   - Users manage their own

4. **availability** - When helpers are free to work
   - Recurring (by day of week) or specific dates
   - Time ranges
   - Viewable by everyone

5. **jobs** - Posted needs/requests
   - Title, description, location
   - Fixed or hourly pricing
   - Status: open → assigned → in_progress → completed/disputed/cancelled
   - Optional pickup offered

6. **applications** - Helpers applying to jobs
   - Message and proposed rate
   - Status: pending → accepted/rejected/withdrawn
   - Only visible to job poster and applicant

7. **messages** - Direct messaging
   - Between any two users
   - Optional job context
   - Read receipts

8. **reviews** - Ratings after job completion
   - 1-5 stars with optional comment
   - Only for completed, non-disputed jobs
   - One review per person per job

9. **transactions** - Escrow payment tracking
   - Money held until job completion
   - Status: pending → held → released/disputed/split/refunded
   - Prepared for Mangopay or Stripe integration

### Security (RLS Policies)

All tables have Row Level Security enabled with appropriate policies:
- Public data (profiles, skills, jobs, reviews) viewable by everyone
- Private data (applications, messages, transactions) only by participants
- Users can only modify their own data

### Automatic Features

- **Auto-profile creation**: When user signs up, profile is created automatically
- **Updated_at timestamps**: Auto-update on changes to profiles, jobs, applications, transactions
- **user_ratings view**: Pre-calculated rating statistics per user

## Applying Migrations

### Option 1: Via Supabase Dashboard (Easiest)

1. Go to your Supabase project: https://supabase.com/dashboard
2. Click on your project (hspubomqztpytlfqpwyn)
3. Go to "SQL Editor" in left sidebar
4. Click "New query"
5. Copy the contents of `migrations/20260123000000_initial_schema.sql`
6. Paste into the editor
7. Click "Run"

### Option 2: Via Supabase CLI (Advanced)

```bash
# Install Supabase CLI if not already installed
npm install -g supabase

# Login to Supabase
supabase login

# Link to your project
supabase link --project-ref hspubomqztpytlfqpwyn

# Apply migrations
supabase db push
```

## Testing the Schema

After applying the migration, you can test by:

1. Sign up a new user in your app
2. Check that a profile was auto-created:
   ```sql
   SELECT * FROM profiles;
   ```

3. View the skills:
   ```sql
   SELECT * FROM skills;
   ```

4. Check the user_ratings view:
   ```sql
   SELECT * FROM user_ratings;
   ```

## Next Steps

After applying this schema, you can:
1. Build the "Post a Job" screen (inserts into `jobs` table)
2. Build the "Post Availability" screen (inserts into `availability` table)
3. Create job browsing/search (queries `jobs` table)
4. Build application flow (inserts into `applications` table)
5. Implement messaging (inserts into `messages` table)

## DAC7 Compliance Note

The `transactions` table is ready for tax reporting. You'll need to query it annually to report workers who earned €2,000+ or had 30+ transactions.

Query for DAC7 reporting:
```sql
SELECT
  p.id,
  p.name,
  p.email,
  COUNT(t.id) as transaction_count,
  SUM(t.amount) as total_earned
FROM profiles p
JOIN jobs j ON j.assigned_to = p.id
JOIN transactions t ON t.job_id = j.id
WHERE t.status = 'released'
  AND EXTRACT(YEAR FROM t.released_at) = 2026
GROUP BY p.id, p.name, p.email
HAVING COUNT(t.id) >= 30 OR SUM(t.amount) >= 2000;
```

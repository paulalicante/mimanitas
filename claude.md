# Mi Manitas

## What This Is

A hyper-local help exchange platform for Alicante, Spain. Neighbors connect to help each other with tasks — painting, gardening, cleaning, moving furniture, etc. Think Wallapop meets TaskRabbit, but for your barrio.

**Domain:** mimanitas.me  
**Live landing page:** https://mimanitas.me

## The Core Principle

**We are a bulletin board, NOT an employer.**

This is critical for Spanish labor law compliance. The platform:
- Does NOT set prices (users negotiate)
- Does NOT assign work (users find each other)
- Does NOT control schedules or methods
- Does NOT rate workers in ways that affect platform access
- Does NOT provide equipment

We are a pure matchmaker. Users find each other, negotiate terms, and complete work. We just provide the connection.

**Why this matters:** Glovo got hit with €79M fine for "falso autónomo" violations. We avoid this by never acting as an employer.

## Business Model

**Revenue:** Subscription fee for people needing help (the "employers")  
**Workers:** Free (they're the supply we need to attract)  
**Target:** €500/month = ~50 paying users at €10/month  
**Launch:** FREE for everyone initially to build volume

**Cost structure:**
- Domain: ~€12/year
- Supabase: Free tier
- Vercel: Free tier
- Payment processor: Transaction fees only when money moves

Patient capital model — Paul has pension income, no burn rate pressure. Can wait years for traction at near-zero cost.

## Tech Stack

- **Frontend:** Flutter Web (single codebase, can add mobile later)
- **Backend:** Supabase (Postgres, auth, realtime, storage)
- **Hosting:** Vercel (auto-deploys from GitHub)
- **Payments:** Mangopay or Stripe Connect (escrow functionality)

## Key Features

### 1. Availability Calendar
Workers show when they're free. Flips the gig model — instead of "here's a job, who wants it?" it's "here's when I'm available, got work for me?"

Perfect for shift workers (like Audel, 21, who has unpredictable schedules) and students.

### 2. Escrow Payment
- Employer deposits when job is agreed
- Worker sees payment is guaranteed
- Work completed
- Employer confirms satisfaction
- Payment released

**Dispute resolution:** If disputed after 7 days, auto 50/50 split. No reviews from either party in disputed transactions. This removes revenge review incentive and keeps platform out of he-said-she-said.

### 3. Pickup Option
Workers can offer to collect employers who live on the outskirts and don't have transport. Solves a real problem in spread-out areas.

### 4. Flexible Pricing
- Fixed price per job, OR
- Hourly rate

User choice, not platform mandate.

### 5. Future: Professional Flash Deals
Licensed tradespeople (electricians, plumbers) post spare capacity at discount. "Electrician in your area tomorrow, 20% off." But this is phase 2.

## Legal Compliance (Spain)

### Employer Classification
Must avoid "falso autónomo" (fake freelancer) classification. Spanish Supreme Court tests:
- Control over work organization
- Workplace rules imposed
- Exclusivity requirements
- Level of supervision

We pass all tests by being hands-off. Pure marketplace.

### DAC7 Tax Reporting (Modelo 238)
Platform must report to Hacienda workers who earn:
- €2,000+ annually, OR
- 30+ transactions

Filed electronically by January 31 each year. Platform is liable for reporting, NOT for worker's tax compliance. Workers see this data in their tax information (like Wallapop model).

### Civil Liability
Article 1902 Código Civil: liability requires action/omission BY platform. As pure intermediary, we're likely protected — we're not party to the transaction. Spain is less litigious than US. Real risk is reputational, not legal.

## MVP Features

1. Landing page ✅ (done)
2. Sign up / login (Supabase auth)
3. Post a need ("I need my fence painted Saturday")
4. Post availability ("I can paint, garden, clean on weekends")
5. Browse/search by location and skill
6. Messaging between users
7. Simple profiles with reviews (only for non-disputed transactions)

## Data Model (Draft)

```
users
  - id
  - email
  - name
  - location (lat/lng or barrio)
  - type (helper | seeker | both)
  - bio
  - created_at

skills
  - id
  - name (painting, gardening, cleaning, moving, etc.)

user_skills
  - user_id
  - skill_id

availability
  - id
  - user_id
  - day_of_week / specific_date
  - start_time
  - end_time
  - recurring (boolean)

jobs
  - id
  - poster_id
  - title
  - description
  - skill_id
  - location
  - price_type (fixed | hourly)
  - price_amount
  - status (open | assigned | completed | disputed)
  - created_at

applications
  - id
  - job_id
  - applicant_id
  - message
  - status (pending | accepted | rejected)

messages
  - id
  - sender_id
  - receiver_id
  - job_id (optional)
  - content
  - created_at

reviews
  - id
  - reviewer_id
  - reviewee_id
  - job_id
  - rating (1-5)
  - comment
  - created_at

transactions
  - id
  - job_id
  - amount
  - status (held | released | disputed | split)
  - created_at
```

## Growth Strategy

**Chicken-egg solution:**
1. Seed supply side — Paul + friends/family as first helpers (5-10 real profiles)
2. Physical marketing — flyers at panadería, neighborhood WhatsApp groups, local Facebook, comunidad presidente
3. Existing Bancos del Tiempo in Alicante — potential partners

**First successful match = word of mouth gold** in tight Spanish community.

## First User Validation

Audel (Paul's 21-year-old stepdaughter):
- Works part-time with unpredictable shift schedule
- Confirmed calendar model is useful — "here's when I'm free" instead of scrambling for gig apps
- Would use it to pick up extra work when available

## File Structure (Target)

```
mimanitas/
  index.html          # Landing page (done)
  claude.md           # This file
  lib/                # Flutter app code
  web/                # Flutter web build
  supabase/
    migrations/       # Database schema
    functions/        # Edge functions if needed
```

## Current Status

- ✅ Name chosen: Mi Manitas
- ✅ Domain registered: mimanitas.me
- ✅ Landing page live on Vercel
- ✅ Flutter app scaffold
- ✅ Supabase project setup
- ✅ Auth flow (login, signup, Google OAuth)
- ✅ Database schema with profiles, jobs, applications, skills
- ✅ Job posting for seekers
- ✅ Job browsing for helpers (with skill filters)
- ✅ Job application system
- ✅ Application management (accept/reject)
- ✅ Profile completion prompts
- ✅ Phone number validation (Spanish format)
- ✅ SMS phone verification (Twilio integration)
- ⏳ Payment & withdrawal system
- ⏳ Review/rating system
- ⏳ Messaging between users

## SMS Phone Verification

**Purpose:** Trust and accountability — verifying phone numbers signals platform seriousness and ensures real contact info on file.

**Implementation:**
- Twilio SMS integration via Supabase Edge Functions
- 6-digit verification codes valid for 10 minutes
- Rate limiting: 1 code per minute per user
- Failed attempt tracking: max 5 attempts before requiring new code
- Database tracking in `verification_codes` table

**User Flow:**
1. User enters phone number (Spanish format: +34 6XX XXX XXX)
2. System validates format
3. User saves phone → navigates to verification screen
4. "Send code" button triggers SMS via Twilio
5. User receives SMS with 6-digit code
6. User enters code
7. System validates and marks `phone_verified = true` in profile
8. User can proceed with action (posting job or applying)

**Backend:**
- `send-verification-code` Edge Function - generates codes, stores in DB, sends SMS
- `verify-code` Edge Function - validates codes, updates profile verification status
- Row Level Security policies on `verification_codes` table

**Cost:** ~$0.01 per SMS (Twilio pricing). With trial account, can only send to verified numbers.

**Why this matters:** Beyond just validation, SMS verification is a trust signal. It shows:
- Platform legitimacy (no "fly by night" operators bother with this)
- User accountability (real phone numbers on file)
- Seeker confidence (helpers are verified, not virtual/Skype numbers)
- Quality filter (deters bad actors)

This is infrastructure for trust in a marketplace where people meet in person.

## Notes for Claude

- Paul is a "vibe coder" — describe what you want, AI writes it
- 45 years computing experience, founded ISP in 1993
- Knows Flutter from other projects
- Prefers simple, working code over elaborate architectures
- Located in Alicante, Spain
- Family includes Michelle (13, fluent Spanish, interested in projects) and Michael (11, plays football)
- All UI copy should be in Spanish for this project

# Mi Manitas

## What This Is

A hyper-local help exchange platform for Alicante, Spain. Neighbors connect to help each other with tasks — painting, gardening, cleaning, moving furniture, etc. Think Wallapop meets TaskRabbit, but for your barrio.

**Domain:** mimanitas.me
**Live landing page:** https://mimanitas.me

**Master project index:** `g:\My Drive\MyProjects\CLAUDE.md` — for cross-project context, shared design tokens, and Paul's workflow rules.

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
- **Payments:** Stripe Connect (Express accounts, destination charges)

## Key Features

### 1. Availability Calendar
Workers show when they're free. Flips the gig model — instead of "here's a job, who wants it?" it's "here's when I'm available, got work for me?"

Perfect for shift workers (like Audel, 21, who has unpredictable schedules) and students.

### 2. Escrow Payment
- Employer deposits when job is agreed (via Stripe Checkout)
- Worker sees payment is guaranteed
- Work completed
- Employer confirms satisfaction
- Payment released immediately

**Design decision (Jan 2026):** No 7-day dispute window. Payment is released immediately when the seeker marks the job as complete. This is simpler for users and follows the Airbnb model (pay out when service is delivered). Dispute handling is manual/out-of-band if needed.

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

### GDPR Data Storage
Under GDPR Article 6(1)(c), we can store data required for legal compliance:

**What we store (legal basis: DAC7/Modelo 238):**
- DNI/NIE — Required for tax reporting
- Annual earnings — Required for tax thresholds
- Transaction count — Required for tax thresholds

**What Stripe stores (not us):**
- IBAN/bank details
- Date of birth
- Full address
- ID verification documents

**Retention:** Tax data must be kept 5 years minimum (Spanish tax law). Delete after statutory period expires.

## Landing Page Design (Feb 2026)

**File:** `index.html` (1,477 lines of HTML/CSS/JS)
**Live at:** https://mimanitas.me
**Status:** Professional, polished design — complete and deployed

### Color Palette:
- Navy dark: `#1E3A5F` (primary dark backgrounds)
- Navy light: `#2A4F7A`
- Orange: `#E85000` (CTAs, accents)
- Gold: `#FFB700` (highlights, badges, "gratis" banner)
- Off-white: `#F8FAFC` (light section backgrounds)
- Card shadow: `rgba(30, 58, 95, 0.08)`

### Typography:
- **Nunito** (headings, bold, 400-800 weight)
- **Inter** (body text, 400-600 weight)

### Page Sections (top to bottom):
1. **Header** — Fixed nav with logo, section links, mobile hamburger menu. Turns dark on scroll.
2. **Hero** — Slideshow of 5 background images rotating every 20s. Heading: "Tu comunidad de ayuda local". Dual CTAs: "Necesito ayuda" | "Quiero ayudar". Gold badge: "Gratis para todos hasta 31 julio 2026".
3. **Stats Strip** — Gold bar with 4 stats: Lanzamiento Q2 2026, Empezamos en Alicante, Pago 100% seguro, Sin comisiones ocultas.
4. **"No Greedy Rabbit"** — Dark navy section. Fat rabbit image + "El ayudante cobra el 100%. Siempre." Comparison: other platforms 20-30% vs MiManitas 0%.
5. **"Cómo funciona"** — 3-step cards: Publica, Comparte tu tiempo, Conecta y listo.
6. **"Hecho para todos"** — Dark navy, 2-column: Necesitas ayuda? (5 bullets) | Quieres ayudar? (5 bullets).
7. **"Características"** — 6 feature cards: Pago en depósito, Calendario de disponibilidad, Mensajería y WhatsApp, Verificación por teléfono, 100% local, Precios transparentes.
8. **Tech Stack** — Dark section with tech tags: Flutter, Dart, Supabase, PostgreSQL, Stripe Connect, Twilio, Deno, TypeScript, Edge Functions, WebSockets, WhatsApp, SMS, Vercel, Web3Forms.
9. **Trust Section** — 4 trust items: Depósito seguro, Usuarios verificados, Garantía 7 días, Cumplimiento legal.
10. **Signup/Waitlist** — White card with form: Name, Email, Message (optional). Uses Web3Forms for email delivery.
11. **FAQ** — 6 accordion items covering pricing, escrow, availability, job types, trust, mobile.
12. **Footer** — Logo, email (hola@mimanitas.me), ward.no link, copyright.

### Design Patterns:
- Scroll-reveal animations via IntersectionObserver with staggered 80ms delays
- Hero slideshow with 4s opacity crossfade
- FAQ accordion with click-to-toggle
- Mobile-first responsive with breakpoints at 640px and 900px
- Lazy loading for non-hero images

### Key Design Decisions:
- Navy + orange + gold palette conveys trust and warmth
- "Fat greedy rabbit" mascot creates memorable anti-commission branding
- Dual CTA in hero addresses both sides of the marketplace
- Gold "gratis" badge creates urgency without feeling salesy
- Tech stack section targets potential partners/investors

## MVP Features

1. Landing page ✅ (done — professional redesign Feb 2026)
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
  - type (helper | seeker) — ONE account = ONE role, no "both"
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

## Current Status (Updated: 2026-02-08)

**Landing page:** DONE and deployed at mimanitas.me
**Flutter app:** Feature-complete, functional, ready for GUI polish
**Current work:** GUI alignment — making the Flutter app match the landing page's polished look

### What's Done:
- ✅ Name chosen: Mi Manitas
- ✅ Domain registered: mimanitas.me
- ✅ Landing page live on Vercel (professional design, navy/orange/gold)
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
- ✅ Review/rating system
- ✅ Messaging between users (conversations, chat screens)
- ✅ Real-time message notifications (Supabase Realtime)
- ✅ Notification queue system with dismiss button
- ✅ Unread message badge on Messages button
- ✅ Payment system with Stripe Connect (see Payment System section below)
- ✅ Stripe webhook handler (payment status, account updates, disputes, payouts)
- ✅ Real-time job notifications (new jobs appear instantly for helpers)
- ✅ Job completion releases payment immediately to helper
- ✅ Notification preferences screen (helpers opt into SMS/email/WhatsApp, filter by skill/barrio/price)
- ✅ SMS notification pipeline (notify-new-job Edge Function sends SMS via Twilio to opted-in helpers)
- ✅ Database webhooks configured (jobs INSERT → notify-new-job, applications INSERT → notify-new-application)
- ✅ Twilio upgraded to paid account (SMS can now reach any number, not just verified)
- ✅ WhatsApp Business sender active (MiManitas, +1 412-419-3947 via Twilio)
- ✅ Premium-gated external notifications (SMS/WhatsApp/email gated by subscription_status + env var)
- ✅ Smart job matching: distance (travel time), skills, availability (see Smart Matching section below)
- ✅ Availability screen for helpers (weekly calendar with time slots)
- ✅ Google Places autocomplete for job addresses and helper home location
- ✅ Helper dashboard on home screen (availability, jobs, upcoming, preferences, payments)
- ✅ Browse jobs date format includes day-of-week (e.g., "Lun, 15 feb")
- ✅ Schedule-based job filtering in browse jobs (calendar icon toggle)
- ✅ WhatsApp message templates created + submitted for Meta approval
- ✅ Job assignment notifications (SMS works, WhatsApp pending template creation)
- ✅ Schedule proposals in messaging (seeker/helper can propose dates for flexible jobs)
- ✅ Schedule conflict prevention (helpers can't be double-booked)
- ✅ Contact banner in job applications (pulsing, navigates to chat)
- ✅ Mobile check-in feature (GPS-verified time tracking for helpers)

### What's Next (Priority Order):
1. **GUI alignment** — Restyle Flutter app to match landing page (see GUI Alignment Plan below)
2. Email notifications via Resend (RESEND_API_KEY not yet configured)
3. WhatsApp job reminders (infrastructure ready, needs template + scheduler)
4. SMS end-to-end testing (no helper has opted in yet)

## Schedule Proposals (Feb 2026)

**Goal:** When a flexible job is assigned, seeker and helper can agree on a specific date/time through messaging.

### How It Works:
1. For flexible jobs (no scheduled date), a 📅 calendar button appears in the chat input
2. Either party taps it and picks a date + time
3. A special "schedule proposal" message is sent
4. The other party sees it with "Aceptar" / "Proponer otra" buttons
5. When accepted:
   - Job's `scheduled_date` and `scheduled_time` are updated
   - Job's `is_flexible` is set to `false`
   - A confirmation message is sent
   - The calendar button disappears (date already agreed)

### Database:
- **Migration:** `supabase/migrations/20260208000000_schedule_proposals.sql`
- Added `message_type` column to messages (default 'text', can be 'schedule_proposal')
- Added `metadata` JSONB column for proposal details: `{proposed_date, proposed_time, status}`
- Status: 'pending', 'accepted', or 'declined'

### Files Modified:
- `app/lib/screens/messages/chat_screen.dart` — Added proposal UI, accept/decline handling, job update

## Mobile Check-in Feature (Feb 2026)

**Goal:** Allow helpers to record their arrival and departure at job sites using GPS verification. Mobile-only feature — web users see a message to use the app.

### How It Works:
1. Helper is assigned to a job and navigates to job detail screen on mobile
2. "Control de tiempo" section appears with check-in button
3. Helper taps "Registrar entrada" when they arrive
4. App gets GPS location and verifies they're within 200m of job location
5. If verified, records check-in time + coordinates, changes job status to `in_progress`
6. Helper taps "Registrar salida" when work is complete
7. App records check-out time + coordinates
8. Work duration is calculated and displayed

### Database:
- **Migration:** `supabase/migrations/20260207000000_check_in_tracking.sql`
- Added to `jobs` table:
  - `checked_in_at` TIMESTAMPTZ — When helper checked in
  - `checked_out_at` TIMESTAMPTZ — When helper checked out
  - `check_in_lat`, `check_in_lng` DOUBLE PRECISION — GPS at check-in
  - `check_out_lat`, `check_out_lng` DOUBLE PRECISION — GPS at check-out

### New Files:
- `app/lib/services/check_in_service.dart` — CheckInService with GPS location, distance calculation, check-in/out methods

### Modified Files:
- `app/lib/screens/jobs/job_detail_screen.dart` — Added `_buildCheckInSection()` widget with platform detection
- `app/pubspec.yaml` — Added `geolocator: ^11.0.0` for GPS

### Platform Detection:
```dart
import 'package:flutter/foundation.dart' show kIsWeb;

if (kIsWeb) {
  // Show "Usa la app móvil" message
} else {
  // Show check-in/out buttons
}
```

### Key Details:
- **Distance threshold:** 200 meters from job location to allow check-in
- **GPS accuracy:** Uses `LocationAccuracy.high`
- **Status flow:** assigned → (check-in) → in_progress → (check-out, job still in_progress) → (seeker marks complete) → completed
- **Web fallback:** Shows info banner telling user to use mobile app
- **Error handling:** Graceful failures with Spanish error messages

## Payment System (Jan 2026)

**Provider:** Stripe Connect (Express accounts)
**Status:** Core flow working end-to-end in sandbox. Tested: post job → apply → pay → assign → complete → payment released → helper sees balance.

### What's Done:
- ✅ Spanish validators (`app/lib/utils/spanish_validators.dart`)
  - DNI validation (8 digits + control letter)
  - NIE validation (X/Y/Z + 7 digits + letter)
  - Spanish IBAN validation (mod-97 algorithm)
  - Phone and postal code validation
- ✅ Database migration (`supabase/migrations/20260128000000_payment_tables.sql`)
  - `stripe_accounts` table (links helpers to Stripe Connect)
  - `payment_intents` table (tracks payments)
  - `withdrawals` table (helper payout requests)
  - `helper_balances` view (calculates available/pending balance)
  - Added `payment_status` and `dispute_window_ends_at` to jobs table
- ✅ Dependencies added (`flutter_stripe`, `url_launcher`)
- ✅ Stripe Sandbox account created
- ✅ Publishable key added to `.env`
- ✅ Edge Functions (all deployed with `--no-verify-jwt`):
  - `create-stripe-account` - Creates Stripe Connect Express account for helpers
  - `check-stripe-status` - Checks helper's Stripe account status
  - `create-checkout-session` - Creates Stripe Checkout for seeker payments
  - `verify-checkout` - Verifies payment completion + sends SMS/WhatsApp notification to helper when assigned
  - `confirm-payment` - Confirms payment and updates job status
  - `handle-stripe-webhooks` - Handles all Stripe webhook events (deployed with `--no-verify-jwt`)
  - `notify-new-job` - Database webhook: notifies helpers when new jobs are posted
- ✅ Payment service (`app/lib/services/payment_service.dart`)
- ✅ Payment setup screen (`app/lib/screens/payments/payment_setup_screen.dart`)
- ✅ Earnings screen (`app/lib/screens/payments/earnings_screen.dart`)
- ✅ Helper onboarding flow with Stripe Connect Express
- ✅ Seeker payment flow with Stripe Checkout
- ✅ Stripe webhook handler (`handle-stripe-webhooks`)
  - `checkout.session.completed` — backup for verify-checkout (catches browser-close cases)
  - `payment_intent.succeeded` / `payment_intent.payment_failed` — payment status tracking
  - `account.updated` — Stripe Connect onboarding progress
  - `charge.dispute.created` — freezes funds on chargeback
  - `payout.paid` / `payout.failed` — helper withdrawal tracking
- ✅ Two Stripe webhook endpoints configured:
  - `mimanitas-payments` (Your account): checkout.session.completed, payment_intent.succeeded, payment_intent.payment_failed, charge.dispute.created
  - `mimanitas-connect` (Connected accounts): account.updated, payout.paid, payout.failed
- ✅ Webhook signature verification with dual secrets (HMAC-SHA256, constant-time comparison)
- ✅ Full payment flow tested end-to-end in sandbox
- ✅ Job completion releases payment immediately (no dispute window)
- ✅ Helper earnings screen shows Disponible/Pendiente/Historial

### Edge Function Auth Pattern:
All Edge Functions use direct token extraction (NOT session-based):
```typescript
const token = authHeader.replace('Bearer ', '')
const { data: { user } } = await supabaseClient.auth.getUser(token)
```

### Test Mode vs Live Mode:
The `create-stripe-account` function auto-detects test vs live mode:
- **Test mode** (`sk_test_*`): Pre-fills fake verification data (DOB, address) so helpers skip Stripe's verification steps
- **Live mode** (`sk_live_*`): Only pre-fills name/email/phone from profile; helpers must provide real verification data

**Test mode values:**
- Test IBAN (Spain): `ES0700120345030000067890`
- Test phone: `+34 600 000 000`
- Address line: `address_full_match` (Stripe magic value)

This happens automatically based on the `STRIPE_SECRET_KEY` prefix. When switching to production:
1. Replace `STRIPE_SECRET_KEY` in Supabase Edge Function Secrets with live key
2. Replace `STRIPE_PUBLISHABLE_KEY` in app `.env` with live key
3. Delete all test `stripe_accounts` rows (they reference test Stripe accounts)

### What's Next:
- ✅ WhatsApp message templates created (pending Meta approval)
- ⏳ Email notifications for new jobs (need RESEND_API_KEY in Supabase secrets)
- ⏳ In-app withdrawal flow for helpers (currently helpers use Stripe dashboard)
- ⏳ Payment history/receipts screen for seekers
- ✅ Edge Functions deployed with premium gate (gate open)
- ✅ `REQUIRE_PREMIUM_NOTIFICATIONS=false` set in Supabase secrets

### Payment Flow:
1. Seeker accepts application → redirected to Stripe Checkout
2. Seeker pays job amount + 10% platform fee
3. Money held by Stripe (destination charges with `transfer_data`)
4. Job status → `assigned`, payment_status → `paid`, transaction status → `held`
5. Seeker marks job complete (via "Completar" button in Mis Trabajos)
6. Payment released immediately: job status → `completed`, payment_status → `released`, transaction → `released`
7. Helper sees balance update in earnings screen (Disponible)
8. Helper can withdraw to Spanish IBAN via Stripe dashboard (or future in-app flow)

**Backup path:** If user closes browser before verify-checkout runs, the `checkout.session.completed` webhook catches it and processes the payment.

### Data Pre-fill Strategy:
In live mode, we only pre-fill data we already have from the user's profile:
- `first_name` / `last_name` — from profile name (if set)
- `email` — always have this from auth
- `phone` — only if user has verified their phone

**We intentionally do NOT collect/store:**
- Date of birth
- Full address
- IBAN/bank details

**Why this is correct:**
1. **GDPR compliance** — We only store data needed for platform operations
2. **Security** — Bank details go directly to Stripe, never touch our servers
3. **Less maintenance** — Stripe's form handles validation, address autocomplete, etc.
4. **User trust** — Stripe's PCI-compliant form is familiar and trusted

Stripe's Express onboarding collects any missing required fields. This is the recommended approach — let Stripe handle the financial KYC.

### Tax Compliance:
- Track `annual_earnings_eur` and `transaction_count` per helper
- Auto-flag when helper reaches €2,000 or 30 transactions (DAC7 threshold)
- Collect DNI/NIE before first withdrawal for Modelo 238 reporting

## Stripe Webhooks

**Two webhook endpoints configured in Stripe Dashboard:**

1. **mimanitas-payments** (Your account events)
   - URL: `https://hspubomqztpytlfqpwyn.supabase.co/functions/v1/handle-stripe-webhooks`
   - Events: checkout.session.completed, payment_intent.succeeded, payment_intent.payment_failed, charge.dispute.created
   - Secret env var: `STRIPE_WEBHOOK_SECRET`

2. **mimanitas-connect** (Connected account events)
   - Same URL
   - Events: account.updated, payout.paid, payout.failed
   - Secret env var: `STRIPE_CONNECT_WEBHOOK_SECRET`

**Signature verification:** The handler tries both secrets sequentially (HMAC-SHA256 with constant-time comparison). Replay protection: rejects timestamps older than 5 minutes.

**Stripe CLI installed** at: `C:\Users\Honey\AppData\Local\Microsoft\WinGet\Packages\Stripe.StripeCli_Microsoft.Winget.Source_8wekyb3d8bbwe\stripe.exe`

## Real-time Notifications

**Implementation:** `app/lib/services/job_notification_service.dart`

- Uses Supabase Realtime to subscribe to `jobs` table INSERT events
- Helper accounts see a MaterialBanner when new jobs are posted
- Notifications persist until user dismisses them or clicks "Ver" (no auto-close)
- "Ver" navigates to the job detail screen
- Database webhook (`notify-new-job`) also fires on job INSERT for push/SMS/email notifications

**Notification preferences:** `supabase/migrations/20260131100000_notification_preferences.sql`
- Users can opt in/out of SMS, email, WhatsApp notifications
- Stored in `notification_preferences` table

## Design Decisions (Jan 2026)

1. **One account = one role.** Users are either a helper OR a seeker, never both. Like Workaway.info. Separate accounts needed if someone wants to be both. This avoids UI complexity and role-switching confusion.

2. **No dispute window.** Payment released immediately when seeker marks job complete. Simpler for users. Disputes handled manually if needed.

3. **Notifications persist.** Job notifications stay on screen until user dismisses or clicks through. No auto-close timer.

4. **Webhook as backup.** The `checkout.session.completed` webhook duplicates what `verify-checkout` does, ensuring payment is recorded even if the user closes their browser during the Stripe redirect.

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

## WhatsApp Business Setup (Jan 2026)

**Goal:** Send WhatsApp notifications to helpers when new jobs are posted.
**Provider:** Twilio WhatsApp Business API
**Status:** ACTIVE — WhatsApp sender registered and live. Ready to send messages.

### What's Done:
- ✅ Twilio upgraded to paid account (was on trial)
- ✅ MiManitas Facebook Page created (category: In-Home Service, website: www.mimanitas.me, city: Alicante)
- ✅ Started Twilio WhatsApp Self Sign-up flow (Twilio Console → Messaging → Senders → WhatsApp Senders)
- ✅ Meta Business Portfolio created (name: "Mi Manitas") — created during Twilio's "Continue with Facebook" popup
- ✅ WhatsApp Business Account (WABA) created — also created during the same popup
- ✅ Twilio number assigned for WhatsApp: +1 (412) 419-3947

### Resolved Issues:
- First attempts mistakenly used Paul's personal Spanish number and Norwegian number — both failed
- The correct approach was to use the **Twilio number** from step 2 of the Self Sign-up page
- Meta API had timeout issues and rate-limited after multiple retries
- Eventually completed successfully — sender is now Online

### WhatsApp Sender Details:
- **Number:** +1 (412) 419-3947
- **Display name:** MiManitas
- **Status:** Online (green checkmark)
- **Throughput:** 80 MPS
- **WABA ID:** 1542890803605593
- **Meta Business Manager ID:** 90230778216886

### WhatsApp Content Templates:
- ✅ **mimanitas_nuevo_trabajo** (`HX849428c56adba4605701346d1606fa1b`): `Mi Manitas: Nuevo trabajo "{{1}}" {{2}} — {{3}}. Abre la app para ver detalles.`
- ✅ **mimanitas_nueva_solicitud** (`HX36e73b51c2a58717bf218c7f1a07f242`): `Mi Manitas: {{1}} ha aplicado a tu trabajo "{{2}}". Abre la app para revisar su solicitud.`
- ⏳ **mimanitas_trabajo_asignado** (PENDING CREATION): `🎉 ¡Enhorabuena! {{1}} te ha contratado para "{{2}}" ({{3}}). Abre la app para ver los detalles.`
  - Variables: `{{1}}` = seeker name, `{{2}}` = job title, `{{3}}` = price (e.g., "50€" or "15€/hora")
  - Category: UTILITY
  - **To create:** Twilio Console → Messaging → Content Template Builder → Create new
  - Once approved, set: `supabase secrets set WA_TEMPLATE_JOB_ASSIGNED=HXxxxxxxxxx`
  - Then update `verify-checkout` to use `ContentSid` + `ContentVariables` instead of `Body`
- Template SIDs stored as Supabase secrets: `WA_TEMPLATE_NEW_JOB`, `WA_TEMPLATE_NEW_APPLICATION`, `WA_TEMPLATE_JOB_ASSIGNED` (pending)
- Edge Functions updated to use `ContentSid` + `ContentVariables` instead of raw `Body`

### What's Next for WhatsApp:
1. **Create job assignment template** (`mimanitas_trabajo_asignado`) in Twilio Console → Content Template Builder
2. Wait for Meta template approval (can check status in Twilio Console → Content Template Builder)
3. Once approved, set `WA_TEMPLATE_JOB_ASSIGNED` secret and update `verify-checkout` to use it
4. Test end-to-end once approved
5. Consider getting a Spanish +34 Twilio number for local trust (~$1-2/month)

### Key Details:
- The WhatsApp sender number is the **Twilio number** (+1 412-419-3947), not a personal number
- Personal WhatsApp and WhatsApp Business API CANNOT share the same phone number
- Twilio verifies their own numbers with Meta — no separate SIM card needed
- Meta Business verification (separate from phone verification) may be required later — takes 5-20 business days
- The `notify-new-job` Edge Function already exists and handles SMS; WhatsApp will be added as an additional channel
- For production, get a Spanish +34 Twilio number (~$1-2/month) for local trust. SMS to Spain costs ~$0.07-0.10/msg from a Spanish number vs ~$0.08-0.12 from US number
- Current US number works fine for testing

## Premium-Gated External Notifications (Feb 2026)

**Concept:** SMS, WhatsApp, and email notifications are premium features. In-app notifications (Supabase Realtime) stay free forever.

**Dual-check:** Both sides must be premium for external notifications to fire:
- **Seekers** must be premium for their posted jobs to trigger external notifications to helpers
- **Helpers** must be premium to receive external notifications about new jobs

### How It Works:
- Uses existing `subscription_status` field on `profiles` table
- `free_trial` or `active` = premium (gets external notifications)
- `cancelled`, `expired`, or `NULL` = not premium (in-app only)
- `REQUIRE_PREMIUM_NOTIFICATIONS` env var controls the gate:
  - `false` (default at launch): gate is open, everyone gets external notifications
  - `true`: only premium users get external notifications

### Implementation:
- **Migration:** `supabase/migrations/20260201000000_ensure_subscription_status.sql` — backfills NULL subscription_status to `free_trial`
- **Edge Functions:** `notify-new-job` and `notify-new-application` both have `isPremium()` helper that checks env var + subscription_status
- **Flutter UI:** `notification_preferences_screen.dart` loads user's subscription_status and disables SMS/Email/WhatsApp toggles if not premium, shows orange "función premium" banner

### To Flip the Gate (Monetize):
```bash
supabase secrets set REQUIRE_PREMIUM_NOTIFICATIONS=true
```
No code deploy needed. Non-premium users' external notifications stop immediately. Their UI toggles grey out on next app load.

### What Stays Free:
- In-app real-time notifications (Supabase Realtime, zero marginal cost)
- All existing app features (messaging, job posting, applying, reviews, etc.)

## Supabase Edge Function Secrets

These environment variables must be set in Supabase Dashboard → Edge Functions → Secrets:

| Secret | Status | Purpose |
|--------|--------|---------|
| `STRIPE_SECRET_KEY` | ✅ Set | Stripe API calls |
| `STRIPE_WEBHOOK_SECRET` | ✅ Set | Verify payment webhook signatures |
| `STRIPE_CONNECT_WEBHOOK_SECRET` | ✅ Set | Verify connect webhook signatures |
| `TWILIO_ACCOUNT_SID` | ✅ Set | SMS verification |
| `TWILIO_AUTH_TOKEN` | ✅ Set | SMS verification |
| `TWILIO_PHONE_NUMBER` | ✅ Set | SMS sender number |
| `GOOGLE_MAPS_API_KEY` | ✅ Set | Google Places autocomplete (smart matching) |
| `RESEND_API_KEY` | ❌ Not set | Email notifications (notify-new-job) |
| `REQUIRE_PREMIUM_NOTIFICATIONS` | ✅ Set (`false`) | Premium gate for external notifications (flip to `true` to monetize) |
| `WA_TEMPLATE_NEW_JOB` | ✅ Set | WhatsApp Content Template SID for new job notifications |
| `WA_TEMPLATE_NEW_APPLICATION` | ✅ Set | WhatsApp Content Template SID for new application notifications |
| `WA_TEMPLATE_JOB_ASSIGNED` | ⏳ Pending | WhatsApp Content Template SID for job assignment notifications (create template first) |

## Smart Job Matching (Feb 2026)

**Goal:** Helpers only get notified about jobs they can realistically do — within their travel time, matching their skills, fitting their schedule.

### How It Works:

Three-pass filter system applied both server-side (Edge Function for SMS/WhatsApp/email) and client-side (Flutter for in-app notifications):

1. **Skills / Barrio / Price** — Existing filters. Barrio filter only applies if helper has NOT set up distance-based filtering (distance takes priority over barrio).

2. **Distance (travel time)** — If job has lat/lng AND helper has home location + transport modes:
   - **Server-side:** Google Distance Matrix API for real travel times (driving, bicycling, walking, transit)
   - **Client-side:** Haversine distance + speed estimates (car 30km/h, transit 20km/h, escooter 15km/h, bike 12km/h, walk 5km/h)
   - Compared against helper's `max_travel_minutes` setting
   - Transport mode mapping: car→driving, bike→bicycling, walk→walking, transit→transit, escooter→bicycling

3. **Availability** — If job has scheduled date/time AND is NOT flexible:
   - Checks helper's `availability` table for matching day + time slot
   - Recurring slots match by day_of_week, specific slots match by exact date
   - Helpers with NO availability records = treated as "always available"

### Graceful Fallbacks:

| Helper has... | Matching behavior |
|---|---|
| Location + transport modes | Distance Matrix API (travel time) |
| Barrio preferences only | Barrio string matching (existing) |
| Neither location nor barrio | Receives all job notifications |
| No availability records | Treated as "always available" |
| Availability records | Only notified for jobs fitting their schedule |

### What Seekers See (Post Job):
- Address field: Google Places autocomplete (type-ahead) → stores lat/lng/barrio
- Scheduling: "Horario flexible" toggle OR date picker + time picker
- Estimated duration dropdown (30min, 1h, 2h, 3h, 4h, medio dia, dia completo)

### What Helpers See (Notification Preferences):
- "Mi ubicacion" — Google Places autocomplete for home address → stores lat/lng to profile
- "Modo de transporte" — Multi-select chips: Coche, Bici, A pie, Bus/Tram, Patinete
- "Tiempo maximo de viaje" — Slider 5-60 min (step 5, default 30)
- Existing skill/barrio/price filters kept as fallbacks

### What Helpers See (Availability Screen):
- Weekly calendar Mon-Sun
- Each day shows time slots as chips
- "+" button per day to add start/end time via pickers
- Accessible from home screen "Publicar disponibilidad" button

### Database Changes:
- **Migration:** `supabase/migrations/20260201200000_smart_matching.sql`
- `notification_preferences`: added `transport_modes TEXT[]`, `max_travel_minutes INTEGER`
- `jobs`: added `is_flexible BOOLEAN`, `estimated_duration_minutes INTEGER`
- Index: `idx_availability_user_dow_date` on availability table

### New Files:
- `supabase/functions/geocode-address/index.ts` — Server-side proxy to Google Maps APIs (autocomplete, details, distance matrix). Hides API key, avoids CORS.
- `app/lib/services/geocoding_service.dart` — Flutter service wrapping geocode-address Edge Function
- `app/lib/widgets/places_autocomplete_field.dart` — Reusable address autocomplete widget with dropdown overlay
- `app/lib/screens/profile/availability_screen.dart` — Weekly availability calendar

### Modified Files:
- `app/lib/screens/jobs/post_job_screen.dart` — Address autocomplete + scheduling fields
- `app/lib/screens/profile/notification_preferences_screen.dart` — Location, transport, travel time sections
- `supabase/functions/notify-new-job/index.ts` — Distance Matrix API calls + availability checking
- `app/lib/services/job_notification_service.dart` — Client-side Haversine distance filter
- `app/lib/screens/home/home_screen.dart` — "Publicar disponibilidad" button wired to AvailabilityScreen

### Google Maps API Setup:
Need a Google Cloud project with these APIs enabled:
- **Places API** (autocomplete)
- **Geocoding API** (address → lat/lng)
- **Distance Matrix API** (travel time by mode)

Set the key: `supabase secrets set GOOGLE_MAPS_API_KEY=<your-key>`

Cost at Mi Manitas scale (~50 users): ~$3-5/month

### Google Cloud Console Steps:
1. Go to https://console.cloud.google.com
2. Create a new project (e.g., "Mi Manitas")
3. Go to "APIs & Services" → "Library"
4. Enable: Places API, Geocoding API, Distance Matrix API
5. Go to "APIs & Services" → "Credentials"
6. Create API key
7. Restrict key: Application restrictions → None (Edge Function uses server-side), API restrictions → restrict to the 3 APIs above
8. Set in Supabase: `supabase secrets set GOOGLE_MAPS_API_KEY=<key>`

## Helper Dashboard (Feb 2026)

**Goal:** Replace the marketing/landing content on the helper home screen with an actionable dashboard showing real data. Seekers still see the existing marketing layout.

### What Helpers See:

When logged in as a helper, the home screen shows 5 dashboard cards instead of the hero/CTA/features marketing sections:

1. **Mi disponibilidad** — 7-day row (L M X J V S D) with orange circles for days with availability set, grey dashes for empty days. Time ranges shown below active days. Taps to AvailabilityScreen.

2. **Trabajos disponibles** — Large orange number showing count of open jobs the helper hasn't applied to yet. Taps to BrowseJobsScreen.

3. **Próximos trabajos** — Up to 3 accepted/assigned jobs with title, seeker name, and date (with day-of-week). Only shows if there are upcoming jobs. "Ver todos" link to MyApplicationsScreen.

4. **Preferencias** — Summary showing home barrio, transport modes + max travel time, and active notification channels. "Pausado" badge if notifications paused. Taps to NotificationPreferencesScreen.

5. **Ganancias** — Two pills side by side: "Disponible" (green) and "Pendiente" (orange) with amounts from `helper_balances` view. Taps to EarningsScreen.

### Implementation:
- **File:** `app/lib/screens/home/home_screen.dart`
- Dashboard data loaded via `_loadDashboardData()` with 5 parallel Supabase queries
- Data refreshes after returning from any sub-screen
- Each loader wrapped in try/catch so one failure doesn't break others
- Shared `_buildDashboardCard()` helper for consistent card styling

### Browse Jobs Date Format:
- **File:** `app/lib/screens/jobs/browse_jobs_screen.dart`
- `_formatScheduleCompact()` now shows day-of-week: "Lun, 15 feb" instead of "15 feb"
- Uses Spanish day abbreviations: dom, lun, mar, mie, jue, vie, sab

### Schedule Filter in Browse Jobs:
- Calendar icon in browse jobs app bar toggles schedule-based filtering
- When active: only shows jobs that fit helper's availability (orange banner: "Solo trabajos que encajan con tu horario")
- When inactive: shows all jobs (green banner: "Mostrando todos los trabajos")
- Icon only appears if helper has availability records set

### Important:
- Adding new state variables to the home screen requires a **hot restart** (Shift+R or stop/start), not just hot reload (r)
- Seekers see the unchanged marketing/landing page layout

## GUI Alignment Plan (Feb 2026)

**Goal:** Upgrade the Flutter app's GUI to match the professional look and feel of the landing page (index.html). Currently the app uses a basic Material3 orange theme while the landing page has a polished navy/orange/gold design.

### Current App GUI:
- Material3 with orange seed color (#E86A33), warm background (#FFFBF5)
- Basic white cards with subtle orange shadows
- No separate theme file — theming inline in main.dart
- Functional but visually plain compared to the landing page

### Target Design (match landing page):
- Navy (#1E3A5F) + orange (#E85000) + gold (#FFB700) color palette
- Nunito headings + Inter body text (matching landing page typography)
- Polished card styles with navy accents
- Professional section headers
- Consistent spacing, shadows, and border radius
- Trust-building visual language (badges, verification indicators)

### What Needs to Change:
- [ ] Create `app/lib/app_theme.dart` with centralized theme matching landing page colors
- [ ] Update main.dart to use new theme
- [ ] Restyle home screen (both helper dashboard and seeker marketing view)
- [ ] Restyle all screen headers and navigation
- [ ] Update card styles across all screens (jobs, messages, profile, etc.)
- [ ] Consistent button styles (orange primary, navy secondary)
- [ ] Typography overhaul (Nunito headings, Inter body)
- [ ] Polish individual screens to match landing page quality level

### Approach:
- Work screen-by-screen, starting with the home screen
- Create a shared theme first, then apply to all screens
- Keep all existing functionality intact — visual upgrade only
- Test on both helper and seeker views

## Future Expansion Vision (Feb 2026)

**Context:** As the Mi Manitas calendar and messaging features matured, a bigger vision emerged: expanding into a calendar-based appointment platform for recurring home services.

### Two-Product Strategy

**Mi Manitas (this app)** — stays focused on its original mission:
- Hyper-local, occasional help exchange
- One-off tasks: painting, gardening, moving, cleaning
- Helper availability calendar for finding work
- Pure matchmaking (bulletin board model)

**Future calendar app** (separate project) — expands the vision:
- Calendar becomes the daily-driver interface
- Appointment-based recurring services: nails, massage, tutoring, personal training
- Users book recurring slots (e.g., "nails every 2 weeks, massage monthly")
- Service providers manage their full schedule in one place
- External calendar sync (Google Calendar, Apple Calendar)
- Recurring appointment reminders via WhatsApp

### Shared Infrastructure

Both apps can share the same backend:
- Supabase project (auth, database, realtime)
- Stripe Connect (payments)
- Twilio (SMS, WhatsApp)
- Google Maps APIs (location services)

This means the investment in Mi Manitas infrastructure pays forward into the expanded product.

### Why Two Apps

1. **Focus** — Mi Manitas has a clear value proposition ("neighbors helping neighbors"). Adding salon bookings would dilute the brand.
2. **Different users** — Occasional task seekers ≠ people booking regular appointments.
3. **Launch simplicity** — Mi Manitas can launch focused while the expanded vision develops.
4. **Patient capital** — No rush. Can wait for Mi Manitas to prove itself before investing in expansion.

### Future Calendar App Features (Parked Ideas)

- Full external calendar sync (OAuth to Google/Apple Calendar)
- Recurring appointment scheduling
- Service provider availability management
- WhatsApp appointment reminders (already have integration!)
- Calendar as the primary interface (not a job board)
- Multi-provider booking (nails + massage in one view)

### For Now

Mi Manitas stays focused. "Add to Calendar" buttons per job are sufficient for the current use case. Full calendar sync and recurring appointments are parked for the future expansion.

## WhatsApp Job Reminders (Near-term)

**Goal:** Send WhatsApp reminders to both helper and seeker before a scheduled job.

### What We Already Have:
- Twilio WhatsApp Business sender (active, working)
- WhatsApp template system (know how to create/submit templates)
- Job scheduling data (scheduled_date, scheduled_time in jobs table)
- Notification preferences (users can opt in/out of WhatsApp)

### What We Need:
1. **New WhatsApp template** (e.g., `mimanitas_recordatorio`):
   - `Recordatorio: Tu trabajo "{{1}}" es mañana a las {{2}}. {{3}}`
   - Variables: job title, time, helper/seeker name
   - Submit via Twilio Content Template Builder

2. **Scheduled Edge Function** (`send-job-reminders`):
   - Runs daily (or hourly) via Supabase pg_cron or external cron
   - Finds jobs scheduled for tomorrow (or in X hours)
   - Checks notification preferences
   - Sends WhatsApp to opted-in helpers and seekers

3. **Reminder tracking**:
   - Add `reminder_sent_at` column to jobs table
   - Prevent duplicate reminders

### Implementation Options:
- **pg_cron** (Supabase Pro feature): Schedule SQL that calls Edge Function
- **External cron**: Use cron-job.org or similar to hit the Edge Function URL
- **Supabase Database Webhooks**: Won't work for scheduled sends (only triggers on row changes)

### Cost:
- WhatsApp template messages: ~$0.02-0.05 per message (utility category)
- At Mi Manitas scale (~50 users): negligible

## Notes for Claude

- Paul is a "vibe coder" — describe what you want, AI writes it
- 45 years computing experience, founded ISP in 1993
- Knows Flutter from other projects
- Prefers simple, working code over elaborate architectures
- Located in Alicante, Spain
- Family includes Michelle (13, fluent Spanish, interested in projects) and Michael (11, plays football)
- All UI copy should be in Spanish for this project
- Paul manages 6 projects simultaneously — tracking what's been done is Claude's responsibility
- Step-by-step guidance needed for unfamiliar tasks (e.g., webhooks, Meta Business verification)

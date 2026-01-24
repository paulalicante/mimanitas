# Mi Manitas - Product Backlog

## High Priority

### Profile Completion Flow
- [ ] Show profile completion progress indicator

### Payment & Withdrawal System
- [ ] Implement helper withdrawal flow
  - [ ] Collect DNI/NIE, address, IBAN when helper first withdraws
  - [ ] Validate DNI/NIE format
  - [ ] Validate IBAN format
  - [ ] Integrate payment provider (Stripe/Mangopay)
- [ ] Transaction tracking for completed jobs
- [ ] Auto-update annual_earnings_eur and transaction_count
- [ ] Tax reporting threshold notifications (DAC7/Modelo 238)

### Job Management
- [ ] Edit job functionality for seekers
- [ ] Cancel/close job before completion
- [ ] Review/rating system after job completion
- [ ] Dispute resolution workflow

### Notifications
- [ ] Push notifications for new applications
- [ ] Email notifications for job status changes
- [ ] In-app notification badge/counter for new accepted applications

## Medium Priority

### Birthday Automation
- [ ] Scheduled job to call get_todays_birthdays()
- [ ] Email template for birthday greetings
- [ ] Birthday special offer system
- [ ] Admin dashboard to configure birthday offers

### Profile Features
- [ ] Profile picture upload (avatar_url)
- [ ] Phone verification with OTP (phone_verified_at)
- [ ] Identity verification (identity_verified_at)
- [ ] Helper skills/experience showcase
- [ ] Helper availability calendar
- [ ] Saved locations for seekers (default_location_address, default_barrio)

### Search & Discovery
- [ ] Location-based job search (using location_lat, location_lng)
- [ ] Distance filtering for jobs
- [ ] Search by barrio
- [ ] Helper search for seekers
- [ ] Featured/promoted jobs

### Travel Time Estimation
- [ ] Add home location (lat/lng) to helper profiles
- [ ] Add transport preferences to helper profiles (walk, bike, car, bus)
- [ ] Set up Google Maps Directions API
- [ ] Create backend proxy/cloud function for API calls
- [ ] **Phase 1: Job Browsing** (simple estimates)
  - [ ] Add "Calcular tiempo" button on job cards
  - [ ] Show quick time estimates for preferred transport modes only
  - [ ] Display as badges: 🚴 12 min · 🚗 5 min · 🚌 25 min
- [ ] **Phase 2: Accepted Jobs** (detailed navigation)
  - [ ] Show full route details with transfers (for transit)
  - [ ] Add "Abrir en Google Maps" button (opens native app with route)
  - [ ] Show step-by-step text instructions in-app
  - [ ] Display departure time suggestions based on job scheduled time
- [ ] **Phase 3: Mobile App** (future - in-app navigation)
  - [ ] Real-time turn-by-turn navigation in Flutter app
  - [ ] Live location tracking
  - [ ] Real-time traffic updates
  - [ ] Alternative route suggestions
- [ ] Cache API results (1 hour) to reduce costs
- [ ] Alternative: Set up OpenTripPlanner with Alicante GTFS data (free but complex)

### Subscription Management (Seekers)
- [ ] Free trial management
- [ ] Subscription payment flow
- [ ] Subscription renewal reminders
- [ ] Subscription plan selection screen
- [ ] Cancel subscription flow

## Low Priority

### Analytics & Reporting
- [ ] Admin dashboard for platform metrics
- [ ] Generate Modelo 238 report (annual tax filing)
- [ ] Helper earnings reports
- [ ] Seeker spending reports
- [ ] Platform usage statistics

### Account Management
- [ ] Account suspension workflow
- [ ] GDPR data export functionality
- [ ] Account deletion (anonymization)
- [ ] User preferences/settings screen
- [ ] Language selection (ES/EN)

### Communication
- [ ] In-app messaging between seekers and helpers
- [ ] Chat history
- [ ] Message notifications
- [ ] Block/report users

### Advanced Features
- [ ] Recurring jobs
- [ ] Job templates for seekers
- [ ] Helper portfolios (before/after photos)
- [ ] Reference system
- [ ] Insurance/guarantee options
- [ ] Multi-helper jobs (team jobs)

## Technical Debt

### Security
- [ ] Implement application-level encryption for sensitive fields (dni_nie, iban, phone)
- [ ] Use Supabase Vault for secrets
- [ ] Rate limiting on API endpoints
- [ ] Input sanitization/validation
- [ ] Security audit

### Performance
- [ ] Optimize application status queries (N+1 problem in browse_jobs_screen.dart)
- [ ] Implement pagination for job listings
- [ ] Cache user profiles
- [ ] Image optimization for avatars
- [ ] Database query optimization

### Testing
- [ ] Unit tests for business logic
- [ ] Widget tests for screens
- [ ] Integration tests for critical flows
- [ ] E2E testing setup

### Infrastructure
- [ ] CI/CD pipeline setup
- [ ] Staging environment
- [ ] Error monitoring (Sentry)
- [ ] Analytics tracking (Firebase Analytics)
- [ ] Automated database backups

## Completed ✓

- [x] Initial database schema
- [x] User signup flow
- [x] Job posting for seekers
- [x] Job browsing for helpers
- [x] Job application system
- [x] Application status tracking
- [x] Accept/reject applications
- [x] Job status updates (open → assigned)
- [x] Application count badges
- [x] Helper profile display (bio, barrio, age)
- [x] Date of birth field
- [x] Age calculation and display
- [x] Birthday query functions
- [x] Tax compliance fields (DNI, IBAN, address)
- [x] Tax reporting tracking (annual_earnings_eur, transaction_count)
- [x] Skill filtering in job browse
- [x] "Otros" miscellaneous skill category
- [x] Supabase CLI migration workflow
- [x] My Applications screen for helpers
- [x] Application status filtering (All/Pending/Accepted/Rejected)
- [x] Contact info display for accepted applications
- [x] Remember me checkbox on login
- [x] Enter key submission on login
- [x] Job completion flow (mark assigned jobs as completed)
- [x] Profile completion prompts for helpers (phone + bio)
- [x] Profile completion prompts for seekers (phone)
- [x] Inline profile editing when applying/posting jobs
- [x] Validate phone number format (Spanish numbers)

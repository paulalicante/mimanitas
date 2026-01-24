# Profile Fields - Data Collection Timeline

This document explains when each profile field is collected to minimize signup friction while ensuring compliance.

## At Signup (Required - Minimal)
- `email` - For login
- `name` - Display name
- `user_type` - Helper or Seeker

## When Posting First Job (Seekers)
- `phone` - So helpers can contact them

## When Applying to First Job (Helpers)
- `phone` - So seekers can contact them
- `bio` - Optional: Tell seekers about yourself and experience
- `date_of_birth` - Optional: For age display and birthday offers

## When Job is Accepted (Optional Convenience)
Prompt user: "Save this location for future jobs?"
- `default_location_address`
- `default_barrio`

## When Helper First Withdraws Money
Before allowing withdrawal, require:
- `dni_nie` - Tax ID (DNI/NIE)
- `address_street`
- `address_city`
- `address_postal_code`
- `iban` - Bank account to receive payment

## Automatic (System Updates)
- `annual_earnings_eur` - Updated after each completed job
- `transaction_count` - Updated after each completed job
- `tax_reporting_required` - Auto-set to `true` when threshold met (€2000/year OR 30 transactions)

## Tax Reporting Thresholds (DAC7 / Modelo 238)

The platform must report to Hacienda when a helper reaches:
- €2,000 in annual earnings, OR
- 30 transactions in a year

When `tax_reporting_required = true`, the platform includes this helper in the annual Modelo 238 filing.

## Verification (Future)
- `phone_verified_at` - Set when phone OTP confirmed
- `identity_verified_at` - Set when DNI/NIE verified (manual or via API)

## Account Status
- `active` - Normal user
- `suspended` - Temporarily blocked (e.g., disputes)
- `pending_verification` - Awaiting identity verification
- `deleted` - Account deleted (GDPR compliance)

## GDPR Compliance

All fields except the signup essentials are optional and only collected when needed. Users can:
- View all their data via Profile screen
- Delete their account (sets `account_status = 'deleted'`, anonymizes data)
- Export their data (future feature)

## Implementation Notes

### Helper Withdrawal Flow
```
1. Helper earns money from completed job
2. Clicks "Withdraw" button
3. IF dni_nie IS NULL:
   - Show form: "To withdraw funds, we need your tax information"
   - Collect: DNI/NIE, address, IBAN
   - Validate format
   - Save to profile
4. Process withdrawal
5. Update annual_earnings_eur and transaction_count
6. Trigger checks if tax_reporting_required should be set
```

### Tax Year Reset
```
Run annually (January 1):
- Reset all profiles: annual_earnings_eur = 0
- Reset all profiles: transaction_count = 0
- Reset all profiles: tax_reporting_required = false
- Generate Modelo 238 report for previous year BEFORE reset
```

### Sensitive Data Encryption
Consider encrypting these fields at application level:
- `dni_nie`
- `iban`
- `phone`

Use Supabase's vault or application-level encryption for production.

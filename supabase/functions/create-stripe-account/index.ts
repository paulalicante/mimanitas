// Supabase Edge Function to create a Stripe Connect Express account for helpers
// This onboards helpers so they can receive payments
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface OnboardingRequest {
  return_url: string  // Where to redirect after onboarding
  refresh_url: string // Where to redirect if link expires
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify auth
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'No authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Extract JWT token
    const token = authHeader.replace('Bearer ', '')

    // Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey)

    // Get authenticated user using token directly
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: authError?.message || 'Invalid token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse request
    const { return_url, refresh_url }: OnboardingRequest = await req.json()

    if (!return_url || !refresh_url) {
      return new Response(
        JSON.stringify({ error: 'return_url and refresh_url are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Admin client for database operations
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    // Get user's profile
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single()

    if (profileError || !profile) {
      return new Response(
        JSON.stringify({ error: 'Profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Only helpers can onboard
    if (profile.user_type !== 'helper') {
      return new Response(
        JSON.stringify({ error: 'Solo los helpers pueden configurar pagos' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if they already have a Stripe account
    const { data: existingAccount } = await supabaseAdmin
      .from('stripe_accounts')
      .select('*')
      .eq('profile_id', user.id)
      .single()

    let stripeAccountId: string

    if (existingAccount?.stripe_account_id) {
      // Use existing account
      stripeAccountId = existingAccount.stripe_account_id

      // In TEST MODE: If account exists but isn't fully verified, add test verification
      const isTestMode = STRIPE_SECRET_KEY?.startsWith('sk_test_')
      if (isTestMode && !existingAccount.onboarding_complete) {
        console.log('Test mode - adding test verification to existing account')

        // Get the person and add test verification document
        const personsResponse = await fetch(
          `https://api.stripe.com/v1/accounts/${stripeAccountId}/persons`,
          {
            headers: {
              'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
            },
          }
        )

        if (personsResponse.ok) {
          const personsData = await personsResponse.json()
          const person = personsData.data?.[0]

          if (person?.id) {
            await fetch(
              `https://api.stripe.com/v1/accounts/${stripeAccountId}/persons/${person.id}`,
              {
                method: 'POST',
                headers: {
                  'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: new URLSearchParams({
                  'verification[document][front]': 'file_identity_document_success',
                  'verification[document][back]': 'file_identity_document_success',
                }),
              }
            )
            console.log('Test verification document added to existing account')
          }
        }
      }
    } else {
      // Detect test mode vs live mode by checking key prefix
      const isTestMode = STRIPE_SECRET_KEY?.startsWith('sk_test_')

      // Create new Stripe Connect Express account
      const helperName = profile.name || 'Helper'
      const nameParts = helperName.split(' ')
      const firstName = nameParts[0] || 'Helper'
      const lastName = nameParts.slice(1).join(' ') || ''

      // Base params for all modes
      const accountParams: Record<string, string> = {
        'type': 'express',
        'country': 'ES',
        'email': profile.email,
        'capabilities[card_payments][requested]': 'true',
        'capabilities[transfers][requested]': 'true',
        'business_type': 'individual',
        'business_profile[mcc]': '7349',
        'business_profile[product_description]': 'Servicios de ayuda local a través de Mi Manitas',
        'business_profile[url]': 'https://mimanitas.me',
        'metadata[profile_id]': user.id,
        'metadata[platform]': 'mimanitas',
      }

      // In TEST MODE ONLY: Pre-fill fake data to skip verification
      // This will be automatically disabled when using live keys
      if (isTestMode) {
        console.log('Test mode detected - pre-filling verification data')
        Object.assign(accountParams, {
          'individual[first_name]': firstName || 'Test',
          'individual[last_name]': lastName || 'User',
          'individual[email]': profile.email,
          'individual[phone]': profile.phone || '+34600000000',
          'individual[dob][day]': '1',
          'individual[dob][month]': '1',
          'individual[dob][year]': '1990',
          'individual[address][line1]': 'address_full_match',
          'individual[address][city]': 'Madrid',
          'individual[address][postal_code]': '28001',
          'individual[address][country]': 'ES',
        })
      } else {
        // LIVE MODE: Only pre-fill name from profile, user must provide rest
        console.log('Live mode - minimal pre-fill, user provides verification data')
        if (firstName) accountParams['individual[first_name]'] = firstName
        if (lastName) accountParams['individual[last_name]'] = lastName
        accountParams['individual[email]'] = profile.email
        if (profile.phone) accountParams['individual[phone]'] = profile.phone
      }

      const createAccountResponse = await fetch('https://api.stripe.com/v1/accounts', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams(accountParams),
      })

      if (!createAccountResponse.ok) {
        const error = await createAccountResponse.text()
        console.error('Stripe account creation error:', error)
        return new Response(
          JSON.stringify({ error: 'Error al crear cuenta de Stripe' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const stripeAccount = await createAccountResponse.json()
      stripeAccountId = stripeAccount.id

      // In TEST MODE: Auto-verify the account using Stripe's test tokens
      // This skips the ID verification step entirely
      if (isTestMode) {
        console.log('Test mode - auto-verifying account with test document')

        // First, get the person ID (for individual accounts, there's one person)
        const personsResponse = await fetch(
          `https://api.stripe.com/v1/accounts/${stripeAccountId}/persons`,
          {
            headers: {
              'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
            },
          }
        )

        if (personsResponse.ok) {
          const personsData = await personsResponse.json()
          const person = personsData.data?.[0]

          if (person?.id) {
            // Update person with test verification document
            // 'file_identity_document_success' is Stripe's magic test token
            await fetch(
              `https://api.stripe.com/v1/accounts/${stripeAccountId}/persons/${person.id}`,
              {
                method: 'POST',
                headers: {
                  'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: new URLSearchParams({
                  'verification[document][front]': 'file_identity_document_success',
                  'verification[document][back]': 'file_identity_document_success',
                }),
              }
            )
            console.log('Test verification document submitted')
          }
        }
      }

      // Save to database
      const { error: insertError } = await supabaseAdmin
        .from('stripe_accounts')
        .insert({
          profile_id: user.id,
          stripe_account_id: stripeAccountId,
          onboarding_complete: false,
          payouts_enabled: false,
          charges_enabled: false,
          details_submitted: false,
        })

      if (insertError) {
        console.error('Database insert error:', insertError)
        return new Response(
          JSON.stringify({ error: `Error al guardar cuenta: ${insertError.message}` }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Create Account Link for onboarding
    const accountLinkResponse = await fetch('https://api.stripe.com/v1/account_links', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        'account': stripeAccountId,
        'refresh_url': refresh_url,
        'return_url': return_url,
        'type': 'account_onboarding',
      }),
    })

    if (!accountLinkResponse.ok) {
      const error = await accountLinkResponse.text()
      console.error('Stripe account link error:', error)
      return new Response(
        JSON.stringify({ error: 'Error al crear enlace de onboarding' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const accountLink = await accountLinkResponse.json()

    return new Response(
      JSON.stringify({
        success: true,
        onboarding_url: accountLink.url,
        stripe_account_id: stripeAccountId,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Error interno del servidor' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

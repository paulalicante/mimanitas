// Supabase Edge Function to check Stripe Connect account status
// Called after helper returns from Stripe onboarding
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify auth
    const authHeader = req.headers.get('Authorization')
    console.log('Auth header present:', !!authHeader)

    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'No authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Extract JWT token from header
    const token = authHeader.replace('Bearer ', '')

    // Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''

    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey)

    // Get authenticated user using the token directly
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)

    console.log('Auth result - user:', user?.id, 'error:', authError?.message)

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: authError?.message || 'Invalid token', details: authError }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Admin client for database operations
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    // Get user's Stripe account
    const { data: stripeAccount, error: accountError } = await supabaseAdmin
      .from('stripe_accounts')
      .select('*')
      .eq('profile_id', user.id)
      .single()

    if (accountError || !stripeAccount) {
      return new Response(
        JSON.stringify({
          has_account: false,
          onboarding_complete: false,
          payouts_enabled: false,
          message: 'No tienes cuenta de Stripe configurada',
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Fetch current status from Stripe
    const stripeResponse = await fetch(
      `https://api.stripe.com/v1/accounts/${stripeAccount.stripe_account_id}`,
      {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
        },
      }
    )

    if (!stripeResponse.ok) {
      const error = await stripeResponse.text()
      console.error('Stripe API error:', error)
      return new Response(
        JSON.stringify({ error: 'Error al consultar Stripe' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const stripeData = await stripeResponse.json()

    // Update our database with current status
    const onboardingComplete = stripeData.details_submitted === true
    const payoutsEnabled = stripeData.payouts_enabled === true
    const chargesEnabled = stripeData.charges_enabled === true

    const { error: updateError } = await supabaseAdmin
      .from('stripe_accounts')
      .update({
        onboarding_complete: onboardingComplete,
        payouts_enabled: payoutsEnabled,
        charges_enabled: chargesEnabled,
        details_submitted: stripeData.details_submitted,
        updated_at: new Date().toISOString(),
      })
      .eq('profile_id', user.id)

    if (updateError) {
      console.error('Database update error:', updateError)
    }

    // Check if there are pending requirements
    const currentlyDue = stripeData.requirements?.currently_due || []
    const pastDue = stripeData.requirements?.past_due || []
    const eventuallyDue = stripeData.requirements?.eventually_due || []
    const hasPendingRequirements = currentlyDue.length > 0 || pastDue.length > 0

    // Determine what message to show
    let message = ''
    let needs_action = false

    if (!stripeData.details_submitted || hasPendingRequirements) {
      // Either hasn't submitted details OR has pending/past due requirements
      if (pastDue.length > 0) {
        message = 'Hay acciones pendientes en tu cuenta de Stripe'
      } else if (currentlyDue.length > 0) {
        message = 'Necesitas completar información adicional en Stripe'
      } else {
        message = 'Necesitas completar el registro en Stripe'
      }
      needs_action = true
    } else if (!payoutsEnabled) {
      message = 'Stripe está verificando tu información. Esto puede tardar unos días.'
      needs_action = false
    } else {
      message = '¡Tu cuenta está lista para recibir pagos!'
      needs_action = false
    }

    console.log('Stripe requirements:', { currentlyDue, pastDue, eventuallyDue, hasPendingRequirements })

    return new Response(
      JSON.stringify({
        has_account: true,
        stripe_account_id: stripeAccount.stripe_account_id,
        onboarding_complete: onboardingComplete,
        payouts_enabled: payoutsEnabled,
        charges_enabled: chargesEnabled,
        details_submitted: stripeData.details_submitted,
        needs_action: needs_action,
        currently_due: currentlyDue.length,
        past_due: pastDue.length,
        eventually_due: eventuallyDue.length,
        message: message,
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

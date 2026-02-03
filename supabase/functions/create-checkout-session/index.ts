// Supabase Edge Function to create a Stripe Checkout Session
// Redirects user to Stripe's hosted payment page
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')
const PLATFORM_FEE_PERCENT = 10 // 10% platform fee

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface CheckoutRequest {
  job_id: string
  application_id: string
  success_url: string
  cancel_url: string
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
    const { job_id, application_id, success_url, cancel_url }: CheckoutRequest = await req.json()

    if (!job_id || !application_id || !success_url || !cancel_url) {
      return new Response(
        JSON.stringify({ error: 'job_id, application_id, success_url, and cancel_url are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Admin client for database operations
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    // Get the job
    const { data: job, error: jobError } = await supabaseAdmin
      .from('jobs')
      .select('*')
      .eq('id', job_id)
      .single()

    if (jobError || !job) {
      return new Response(
        JSON.stringify({ error: 'Trabajo no encontrado' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify user is the job poster
    if (job.poster_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'Solo el propietario puede pagar este trabajo' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check job status
    if (job.status !== 'open') {
      return new Response(
        JSON.stringify({ error: 'Este trabajo ya no está disponible' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the application
    const { data: application, error: appError } = await supabaseAdmin
      .from('applications')
      .select('*, applicant:profiles(name)')
      .eq('id', application_id)
      .eq('job_id', job_id)
      .single()

    if (appError || !application) {
      return new Response(
        JSON.stringify({ error: 'Solicitud no encontrada' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get helper's Stripe account
    const { data: helperStripeAccount, error: stripeAccError } = await supabaseAdmin
      .from('stripe_accounts')
      .select('*')
      .eq('profile_id', application.applicant_id)
      .single()

    if (stripeAccError || !helperStripeAccount) {
      return new Response(
        JSON.stringify({
          error: 'El helper no tiene cuenta de pago configurada',
          helper_needs_onboarding: true,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!helperStripeAccount.payouts_enabled) {
      return new Response(
        JSON.stringify({
          error: 'La cuenta de pago del helper no está activa todavía',
          helper_needs_onboarding: true,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Calculate amounts (in cents)
    const jobAmountCents = Math.round(job.price_amount * 100)
    const platformFeeCents = Math.round(jobAmountCents * PLATFORM_FEE_PERCENT / 100)
    const totalAmountCents = jobAmountCents + platformFeeCents

    const helperName = application.applicant?.name || 'Helper'

    // Create Checkout Session
    const checkoutParams = new URLSearchParams({
      'mode': 'payment',
      'success_url': `${success_url}?session_id={CHECKOUT_SESSION_ID}`,
      'cancel_url': cancel_url,
      'payment_method_types[]': 'card',
      'line_items[0][price_data][currency]': 'eur',
      'line_items[0][price_data][product_data][name]': job.title,
      'line_items[0][price_data][product_data][description]': `Trabajo realizado por ${helperName}`,
      'line_items[0][price_data][unit_amount]': jobAmountCents.toString(),
      'line_items[0][quantity]': '1',
      'line_items[1][price_data][currency]': 'eur',
      'line_items[1][price_data][product_data][name]': 'Comisión Mi Manitas (10%)',
      'line_items[1][price_data][product_data][description]': 'Comisión de la plataforma',
      'line_items[1][price_data][unit_amount]': platformFeeCents.toString(),
      'line_items[1][quantity]': '1',
      'payment_intent_data[transfer_data][destination]': helperStripeAccount.stripe_account_id,
      'payment_intent_data[transfer_data][amount]': jobAmountCents.toString(),
      'payment_intent_data[metadata][job_id]': job_id,
      'payment_intent_data[metadata][application_id]': application_id,
      'payment_intent_data[metadata][helper_id]': application.applicant_id,
      'payment_intent_data[metadata][seeker_id]': user.id,
      'payment_intent_data[metadata][platform]': 'mimanitas',
      'metadata[job_id]': job_id,
      'metadata[application_id]': application_id,
    })

    const checkoutResponse = await fetch('https://api.stripe.com/v1/checkout/sessions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: checkoutParams,
    })

    if (!checkoutResponse.ok) {
      const error = await checkoutResponse.text()
      console.error('Stripe Checkout error:', error)
      return new Response(
        JSON.stringify({ error: 'Error al crear sesión de pago' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const checkoutSession = await checkoutResponse.json()

    // Save to payment_intents table for tracking
    await supabaseAdmin
      .from('payment_intents')
      .insert({
        job_id: job_id,
        stripe_payment_intent_id: checkoutSession.payment_intent || checkoutSession.id,
        amount_cents: jobAmountCents,
        platform_fee_cents: platformFeeCents,
        currency: 'eur',
        status: 'requires_payment_method',
        client_secret: checkoutSession.id, // Store session ID for verification
      })

    return new Response(
      JSON.stringify({
        success: true,
        checkout_url: checkoutSession.url,
        session_id: checkoutSession.id,
        amount_cents: totalAmountCents,
        job_amount_cents: jobAmountCents,
        platform_fee_cents: platformFeeCents,
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

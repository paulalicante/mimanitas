// Supabase Edge Function to create a Stripe PaymentIntent
// Called when seeker accepts an application and pays for the job
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')
const PLATFORM_FEE_PERCENT = 10 // 10% platform fee

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface PaymentRequest {
  job_id: string
  application_id: string
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

    // Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    // Get authenticated user
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse request
    const { job_id, application_id }: PaymentRequest = await req.json()

    if (!job_id || !application_id) {
      return new Response(
        JSON.stringify({ error: 'job_id and application_id are required' }),
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

    // Check if already paid
    if (job.payment_status === 'paid') {
      return new Response(
        JSON.stringify({ error: 'Este trabajo ya está pagado' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the application
    const { data: application, error: appError } = await supabaseAdmin
      .from('applications')
      .select('*, applicant:profiles(*)')
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

    // Create PaymentIntent with transfer to helper's Connect account
    // Using "destination charges" - we charge the customer, then transfer to helper
    const paymentIntentParams = new URLSearchParams({
      'amount': totalAmountCents.toString(),
      'currency': 'eur',
      'payment_method_types[]': 'card',
      'capture_method': 'automatic', // Charge immediately
      'metadata[job_id]': job_id,
      'metadata[application_id]': application_id,
      'metadata[helper_id]': application.applicant_id,
      'metadata[seeker_id]': user.id,
      'metadata[platform]': 'mimanitas',
      // Transfer data - funds go to helper's Connect account minus our fee
      'transfer_data[destination]': helperStripeAccount.stripe_account_id,
      'transfer_data[amount]': jobAmountCents.toString(), // Helper gets job amount, we keep the fee
      'description': `Mi Manitas - ${job.title}`,
    })

    const paymentIntentResponse = await fetch('https://api.stripe.com/v1/payment_intents', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: paymentIntentParams,
    })

    if (!paymentIntentResponse.ok) {
      const error = await paymentIntentResponse.text()
      console.error('Stripe PaymentIntent error:', error)
      return new Response(
        JSON.stringify({ error: 'Error al crear el pago' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const paymentIntent = await paymentIntentResponse.json()

    // Save payment intent to database
    const { error: insertError } = await supabaseAdmin
      .from('payment_intents')
      .insert({
        job_id: job_id,
        stripe_payment_intent_id: paymentIntent.id,
        amount_cents: jobAmountCents,
        platform_fee_cents: platformFeeCents,
        currency: 'eur',
        status: paymentIntent.status,
        client_secret: paymentIntent.client_secret,
      })

    if (insertError) {
      console.error('Database insert error:', insertError)
      // Continue anyway - the payment can still be completed
    }

    return new Response(
      JSON.stringify({
        success: true,
        client_secret: paymentIntent.client_secret,
        payment_intent_id: paymentIntent.id,
        amount_cents: totalAmountCents,
        job_amount_cents: jobAmountCents,
        platform_fee_cents: platformFeeCents,
        currency: 'eur',
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

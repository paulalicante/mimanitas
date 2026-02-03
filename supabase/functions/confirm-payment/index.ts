// Supabase Edge Function to confirm payment success and update job status
// Called after seeker completes payment in the app
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ConfirmRequest {
  payment_intent_id: string
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
    const { payment_intent_id, job_id, application_id }: ConfirmRequest = await req.json()

    if (!payment_intent_id || !job_id || !application_id) {
      return new Response(
        JSON.stringify({ error: 'payment_intent_id, job_id, and application_id are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Admin client for database operations
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    // Verify the job belongs to this user
    const { data: job, error: jobError } = await supabaseAdmin
      .from('jobs')
      .select('*')
      .eq('id', job_id)
      .single()

    if (jobError || !job || job.poster_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'Trabajo no encontrado o no autorizado' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify payment intent with Stripe
    const stripeResponse = await fetch(
      `https://api.stripe.com/v1/payment_intents/${payment_intent_id}`,
      {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
        },
      }
    )

    if (!stripeResponse.ok) {
      return new Response(
        JSON.stringify({ error: 'Error al verificar el pago' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const paymentIntent = await stripeResponse.json()

    // Check payment status
    if (paymentIntent.status !== 'succeeded') {
      return new Response(
        JSON.stringify({
          error: 'El pago no se ha completado',
          payment_status: paymentIntent.status,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the application
    const { data: application, error: appError } = await supabaseAdmin
      .from('applications')
      .select('*')
      .eq('id', application_id)
      .single()

    if (appError || !application) {
      return new Response(
        JSON.stringify({ error: 'Solicitud no encontrada' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Update everything in a transaction-like manner
    // 1. Update payment intent status
    await supabaseAdmin
      .from('payment_intents')
      .update({
        status: 'succeeded',
        updated_at: new Date().toISOString(),
      })
      .eq('stripe_payment_intent_id', payment_intent_id)

    // 2. Accept the application
    await supabaseAdmin
      .from('applications')
      .update({
        status: 'accepted',
        updated_at: new Date().toISOString(),
      })
      .eq('id', application_id)

    // 3. Reject other pending applications for this job
    await supabaseAdmin
      .from('applications')
      .update({
        status: 'rejected',
        updated_at: new Date().toISOString(),
      })
      .eq('job_id', job_id)
      .eq('status', 'pending')
      .neq('id', application_id)

    // 4. Update job status
    const { error: updateError } = await supabaseAdmin
      .from('jobs')
      .update({
        status: 'assigned',
        assigned_to: application.applicant_id,
        payment_status: 'paid',
        updated_at: new Date().toISOString(),
      })
      .eq('id', job_id)

    if (updateError) {
      console.error('Job update error:', updateError)
      return new Response(
        JSON.stringify({ error: 'Error al actualizar el trabajo' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 5. Create transaction record
    const amountEur = paymentIntent.transfer_data?.amount
      ? paymentIntent.transfer_data.amount / 100
      : paymentIntent.amount / 100

    await supabaseAdmin
      .from('transactions')
      .insert({
        job_id: job_id,
        amount: amountEur,
        currency: 'EUR',
        status: 'held', // Money is held until job completed + 7 days
        payment_provider: 'stripe',
        provider_transaction_id: payment_intent_id,
        stripe_payment_intent_id: payment_intent_id,
        platform_fee_amount: (paymentIntent.amount - (paymentIntent.transfer_data?.amount || paymentIntent.amount)) / 100,
        held_at: new Date().toISOString(),
      })

    return new Response(
      JSON.stringify({
        success: true,
        message: '¡Pago completado! El trabajo ha sido asignado.',
        job_status: 'assigned',
        payment_status: 'paid',
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

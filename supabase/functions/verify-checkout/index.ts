// Supabase Edge Function to verify a Stripe Checkout Session
// Called after user returns from Stripe payment page
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface VerifyRequest {
  session_id: string
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
    const { session_id }: VerifyRequest = await req.json()

    if (!session_id) {
      return new Response(
        JSON.stringify({ error: 'session_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Retrieve the Checkout Session from Stripe
    const stripeResponse = await fetch(
      `https://api.stripe.com/v1/checkout/sessions/${session_id}?expand[]=payment_intent`,
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
        JSON.stringify({ error: 'Error al verificar el pago' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const session = await stripeResponse.json()

    // Check payment status
    if (session.payment_status !== 'paid') {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'El pago no se ha completado',
          payment_status: session.payment_status,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get metadata
    const jobId = session.metadata?.job_id
    const applicationId = session.metadata?.application_id

    if (!jobId || !applicationId) {
      return new Response(
        JSON.stringify({ error: 'Datos de pago incompletos' }),
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
      .eq('id', jobId)
      .single()

    if (jobError || !job || job.poster_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'Trabajo no encontrado o no autorizado' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if already processed
    if (job.payment_status === 'paid') {
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Este pago ya fue procesado',
          already_processed: true,
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the application
    const { data: application, error: appError } = await supabaseAdmin
      .from('applications')
      .select('*')
      .eq('id', applicationId)
      .single()

    if (appError || !application) {
      return new Response(
        JSON.stringify({ error: 'Solicitud no encontrada' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const paymentIntentId = typeof session.payment_intent === 'string'
      ? session.payment_intent
      : session.payment_intent?.id

    // Update everything
    // 1. Update payment intent status
    await supabaseAdmin
      .from('payment_intents')
      .update({
        status: 'succeeded',
        stripe_payment_intent_id: paymentIntentId,
        updated_at: new Date().toISOString(),
      })
      .eq('client_secret', session_id)

    // 2. Accept the application
    await supabaseAdmin
      .from('applications')
      .update({
        status: 'accepted',
        updated_at: new Date().toISOString(),
      })
      .eq('id', applicationId)

    // 3. Reject other pending applications for this job
    await supabaseAdmin
      .from('applications')
      .update({
        status: 'rejected',
        updated_at: new Date().toISOString(),
      })
      .eq('job_id', jobId)
      .eq('status', 'pending')
      .neq('id', applicationId)

    // 4. Update job status
    await supabaseAdmin
      .from('jobs')
      .update({
        status: 'assigned',
        assigned_to: application.applicant_id,
        payment_status: 'paid',
        updated_at: new Date().toISOString(),
      })
      .eq('id', jobId)

    // 5. Create transaction record
    const amountEur = session.amount_total ? session.amount_total / 100 : job.price_amount

    await supabaseAdmin
      .from('transactions')
      .insert({
        job_id: jobId,
        amount: job.price_amount,
        currency: 'EUR',
        status: 'held',
        payment_provider: 'stripe',
        provider_transaction_id: paymentIntentId,
        stripe_payment_intent_id: paymentIntentId,
        platform_fee_amount: job.price_amount * 0.1,
        held_at: new Date().toISOString(),
      })

    return new Response(
      JSON.stringify({
        success: true,
        message: '¡Pago completado! El trabajo ha sido asignado.',
        job_id: jobId,
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

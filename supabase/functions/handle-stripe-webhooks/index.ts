// Supabase Edge Function to handle Stripe webhook events
// Called by Stripe when payment/account/payout events occur
// No user auth — verified by Stripe webhook signature
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')
const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET')
const STRIPE_CONNECT_WEBHOOK_SECRET = Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET')

// Verify Stripe webhook signature using HMAC-SHA256
async function verifyStripeSignature(
  body: string,
  signatureHeader: string,
  secret: string,
): Promise<boolean> {
  const parts = signatureHeader.split(',')
  const timestamp = parts.find(p => p.startsWith('t='))?.split('=')[1]
  const signature = parts.find(p => p.startsWith('v1='))?.split('=')[1]

  if (!timestamp || !signature) return false

  // Reject if timestamp is older than 5 minutes (replay protection)
  const now = Math.floor(Date.now() / 1000)
  if (now - parseInt(timestamp) > 300) return false

  // Compute expected signature
  const payload = `${timestamp}.${body}`
  const encoder = new TextEncoder()
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signatureBytes = await crypto.subtle.sign('HMAC', key, encoder.encode(payload))
  const expectedSignature = Array.from(new Uint8Array(signatureBytes))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')

  // Constant-time comparison
  if (expectedSignature.length !== signature.length) return false
  let result = 0
  for (let i = 0; i < expectedSignature.length; i++) {
    result |= expectedSignature.charCodeAt(i) ^ signature.charCodeAt(i)
  }
  return result === 0
}

Deno.serve(async (req) => {
  // Only accept POST
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  try {
    const body = await req.text()
    const signatureHeader = req.headers.get('stripe-signature')

    // Verify signature against both secrets (payments + connect)
    if (!signatureHeader) {
      console.error('Missing signature header')
      return new Response('Missing signature', { status: 400 })
    }

    const secrets = [STRIPE_WEBHOOK_SECRET, STRIPE_CONNECT_WEBHOOK_SECRET].filter(Boolean) as string[]
    if (secrets.length === 0) {
      console.error('No webhook secrets configured')
      return new Response('Webhook secret not configured', { status: 500 })
    }

    let isValid = false
    for (const secret of secrets) {
      if (await verifyStripeSignature(body, signatureHeader, secret)) {
        isValid = true
        break
      }
    }
    if (!isValid) {
      console.error('Invalid webhook signature')
      return new Response('Invalid signature', { status: 400 })
    }

    const event = JSON.parse(body)
    console.log(`Webhook received: ${event.type} (${event.id})`)

    // Create admin Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    // Route to handler
    switch (event.type) {
      case 'checkout.session.completed':
        await handleCheckoutCompleted(supabaseAdmin, event.data.object)
        break

      case 'payment_intent.succeeded':
        await handlePaymentIntentSucceeded(supabaseAdmin, event.data.object)
        break

      case 'payment_intent.payment_failed':
        await handlePaymentIntentFailed(supabaseAdmin, event.data.object)
        break

      case 'account.updated':
        await handleAccountUpdated(supabaseAdmin, event.data.object)
        break

      case 'charge.dispute.created':
        await handleDisputeCreated(supabaseAdmin, event.data.object)
        break

      case 'payout.paid':
        await handlePayoutPaid(supabaseAdmin, event.data.object)
        break

      case 'payout.failed':
        await handlePayoutFailed(supabaseAdmin, event.data.object)
        break

      default:
        console.log(`Unhandled event type: ${event.type}`)
    }

    // Always return 200 to acknowledge receipt
    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Webhook error:', error)
    // Return 200 even on error to prevent Stripe retries for bad data
    // Only return non-200 for signature failures (above)
    return new Response(JSON.stringify({ received: true, error: 'Processing error' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

// ============================================================================
// checkout.session.completed
// Backup for frontend verify-checkout — ensures payment is recorded even if
// the user closes their browser before the redirect completes
// ============================================================================
async function handleCheckoutCompleted(
  supabaseAdmin: ReturnType<typeof createClient>,
  session: Record<string, unknown>,
) {
  const jobId = (session.metadata as Record<string, string>)?.job_id
  const applicationId = (session.metadata as Record<string, string>)?.application_id

  if (!jobId || !applicationId) {
    console.log('checkout.session.completed: missing metadata, skipping')
    return
  }

  // Check if already processed (idempotency)
  const { data: job } = await supabaseAdmin
    .from('jobs')
    .select('payment_status')
    .eq('id', jobId)
    .single()

  if (job?.payment_status === 'paid') {
    console.log(`checkout.session.completed: job ${jobId} already paid, skipping`)
    return
  }

  // Only process if payment was successful
  if (session.payment_status !== 'paid') {
    console.log(`checkout.session.completed: payment_status is ${session.payment_status}, skipping`)
    return
  }

  const paymentIntentId = typeof session.payment_intent === 'string'
    ? session.payment_intent
    : (session.payment_intent as Record<string, unknown>)?.id as string

  // Get the application to find the helper
  const { data: application } = await supabaseAdmin
    .from('applications')
    .select('applicant_id')
    .eq('id', applicationId)
    .single()

  if (!application) {
    console.error(`checkout.session.completed: application ${applicationId} not found`)
    return
  }

  // Get job details for transaction amount
  const { data: jobDetails } = await supabaseAdmin
    .from('jobs')
    .select('price_amount')
    .eq('id', jobId)
    .single()

  // 1. Update payment intent status
  await supabaseAdmin
    .from('payment_intents')
    .update({
      status: 'succeeded',
      stripe_payment_intent_id: paymentIntentId,
      updated_at: new Date().toISOString(),
    })
    .eq('job_id', jobId)

  // 2. Accept the application
  await supabaseAdmin
    .from('applications')
    .update({
      status: 'accepted',
      updated_at: new Date().toISOString(),
    })
    .eq('id', applicationId)

  // 3. Reject other pending applications
  await supabaseAdmin
    .from('applications')
    .update({
      status: 'rejected',
      updated_at: new Date().toISOString(),
    })
    .eq('job_id', jobId)
    .eq('status', 'pending')
    .neq('id', applicationId)

  // 4. Update job
  await supabaseAdmin
    .from('jobs')
    .update({
      status: 'assigned',
      assigned_to: application.applicant_id,
      payment_status: 'paid',
      updated_at: new Date().toISOString(),
    })
    .eq('id', jobId)

  // 5. Create transaction record (if not already exists)
  const { data: existingTx } = await supabaseAdmin
    .from('transactions')
    .select('id')
    .eq('job_id', jobId)
    .single()

  if (!existingTx) {
    const priceAmount = jobDetails?.price_amount || 0
    await supabaseAdmin
      .from('transactions')
      .insert({
        job_id: jobId,
        amount: priceAmount,
        currency: 'EUR',
        status: 'held',
        payment_provider: 'stripe',
        provider_transaction_id: paymentIntentId,
        stripe_payment_intent_id: paymentIntentId,
        platform_fee_amount: priceAmount * 0.1,
        held_at: new Date().toISOString(),
      })
  }

  console.log(`checkout.session.completed: job ${jobId} payment processed`)
}

// ============================================================================
// payment_intent.succeeded
// Updates payment_intents table status — confirms the charge went through
// ============================================================================
async function handlePaymentIntentSucceeded(
  supabaseAdmin: ReturnType<typeof createClient>,
  paymentIntent: Record<string, unknown>,
) {
  const stripeId = paymentIntent.id as string

  const { error } = await supabaseAdmin
    .from('payment_intents')
    .update({
      status: 'succeeded',
      updated_at: new Date().toISOString(),
    })
    .eq('stripe_payment_intent_id', stripeId)

  if (error) {
    console.error(`payment_intent.succeeded: update error for ${stripeId}`, error)
  } else {
    console.log(`payment_intent.succeeded: ${stripeId} updated`)
  }
}

// ============================================================================
// payment_intent.payment_failed
// Marks payment as failed, reverts job to open if it was being assigned
// ============================================================================
async function handlePaymentIntentFailed(
  supabaseAdmin: ReturnType<typeof createClient>,
  paymentIntent: Record<string, unknown>,
) {
  const stripeId = paymentIntent.id as string
  const metadata = paymentIntent.metadata as Record<string, string> | undefined
  const jobId = metadata?.job_id

  // Update payment_intents status
  await supabaseAdmin
    .from('payment_intents')
    .update({
      status: 'canceled',
      updated_at: new Date().toISOString(),
    })
    .eq('stripe_payment_intent_id', stripeId)

  // If we have a job_id, make sure the job stays/returns to open
  if (jobId) {
    const { data: job } = await supabaseAdmin
      .from('jobs')
      .select('status, payment_status')
      .eq('id', jobId)
      .single()

    // Only revert if payment hasn't already succeeded via another path
    if (job && job.payment_status !== 'paid') {
      await supabaseAdmin
        .from('jobs')
        .update({
          status: 'open',
          payment_status: 'unpaid',
          assigned_to: null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', jobId)
    }
  }

  const failureMessage = (paymentIntent.last_payment_error as Record<string, unknown>)?.message || 'unknown'
  console.log(`payment_intent.payment_failed: ${stripeId} — ${failureMessage}`)
}

// ============================================================================
// account.updated
// Stripe Connect account status changed (onboarding progress, payouts enabled)
// ============================================================================
async function handleAccountUpdated(
  supabaseAdmin: ReturnType<typeof createClient>,
  account: Record<string, unknown>,
) {
  const stripeAccountId = account.id as string

  const { error } = await supabaseAdmin
    .from('stripe_accounts')
    .update({
      onboarding_complete: account.details_submitted === true,
      payouts_enabled: account.payouts_enabled === true,
      charges_enabled: account.charges_enabled === true,
      details_submitted: account.details_submitted === true,
      updated_at: new Date().toISOString(),
    })
    .eq('stripe_account_id', stripeAccountId)

  if (error) {
    // Account might not be in our DB yet (e.g., created but not saved)
    console.log(`account.updated: no matching account for ${stripeAccountId}`)
  } else {
    console.log(`account.updated: ${stripeAccountId} — payouts_enabled=${account.payouts_enabled}, charges_enabled=${account.charges_enabled}`)
  }
}

// ============================================================================
// charge.dispute.created
// Customer initiated a chargeback — freeze the job's funds
// ============================================================================
async function handleDisputeCreated(
  supabaseAdmin: ReturnType<typeof createClient>,
  dispute: Record<string, unknown>,
) {
  const paymentIntentId = dispute.payment_intent as string

  if (!paymentIntentId) {
    console.log('charge.dispute.created: no payment_intent on dispute, skipping')
    return
  }

  // Find the job via payment_intents table
  const { data: paymentRecord } = await supabaseAdmin
    .from('payment_intents')
    .select('job_id')
    .eq('stripe_payment_intent_id', paymentIntentId)
    .single()

  if (!paymentRecord) {
    console.log(`charge.dispute.created: no payment_intent record for ${paymentIntentId}`)
    return
  }

  // Update job payment status to disputed
  await supabaseAdmin
    .from('jobs')
    .update({
      payment_status: 'refunded', // Stripe holds funds during dispute
      updated_at: new Date().toISOString(),
    })
    .eq('id', paymentRecord.job_id)

  // Update transaction status
  await supabaseAdmin
    .from('transactions')
    .update({
      status: 'disputed',
      updated_at: new Date().toISOString(),
    })
    .eq('stripe_payment_intent_id', paymentIntentId)

  const amount = dispute.amount as number
  console.log(`charge.dispute.created: dispute for ${amount} cents on PI ${paymentIntentId}, job ${paymentRecord.job_id}`)
}

// ============================================================================
// payout.paid
// Helper's withdrawal arrived at their bank account
// ============================================================================
async function handlePayoutPaid(
  supabaseAdmin: ReturnType<typeof createClient>,
  payout: Record<string, unknown>,
) {
  const payoutId = payout.id as string

  const { error } = await supabaseAdmin
    .from('withdrawals')
    .update({
      status: 'paid',
      paid_at: new Date().toISOString(),
    })
    .eq('stripe_payout_id', payoutId)

  if (error) {
    // Payout might be automatic (not initiated through our platform)
    console.log(`payout.paid: no matching withdrawal for ${payoutId}`)
  } else {
    console.log(`payout.paid: ${payoutId} completed`)
  }
}

// ============================================================================
// payout.failed
// Helper's withdrawal failed (bad IBAN, insufficient funds in account, etc.)
// ============================================================================
async function handlePayoutFailed(
  supabaseAdmin: ReturnType<typeof createClient>,
  payout: Record<string, unknown>,
) {
  const payoutId = payout.id as string
  const failureCode = (payout.failure_code as string) || 'unknown'
  const failureMessage = (payout.failure_message as string) || 'Fallo en la transferencia'

  const { error } = await supabaseAdmin
    .from('withdrawals')
    .update({
      status: 'failed',
      failure_code: failureCode,
      failure_message: failureMessage,
    })
    .eq('stripe_payout_id', payoutId)

  if (error) {
    console.log(`payout.failed: no matching withdrawal for ${payoutId}`)
  } else {
    console.log(`payout.failed: ${payoutId} — ${failureCode}: ${failureMessage}`)
  }
}

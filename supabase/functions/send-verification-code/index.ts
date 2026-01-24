// Supabase Edge Function to send SMS verification codes via Twilio
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID')
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN')
const TWILIO_PHONE_NUMBER = Deno.env.get('TWILIO_PHONE_NUMBER')

interface VerificationRequest {
  phone: string
}

// Generate a random 6-digit verification code
function generateCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString()
}

// Send SMS via Twilio API
async function sendSMS(to: string, code: string): Promise<boolean> {
  const twilioUrl = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`

  const body = new URLSearchParams({
    To: to,
    From: TWILIO_PHONE_NUMBER!,
    Body: `Tu código de verificación de Mi Manitas es: ${code}. Válido por 10 minutos.`
  })

  const auth = btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`)

  const response = await fetch(twilioUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: body.toString(),
  })

  if (!response.ok) {
    const error = await response.text()
    console.error('Twilio API error:', error)
    return false
  }

  return true
}

Deno.serve(async (req) => {
  try {
    // Get authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'No authorization header' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Get user from auth header
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Parse request body
    const { phone }: VerificationRequest = await req.json()

    if (!phone || phone.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'Phone number is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Validate Spanish phone format
    const phoneRegex = /^(\+34|0034)?[6-9]\d{8}$/
    const cleanedPhone = phone.replace(/\s+/g, '')
    if (!phoneRegex.test(cleanedPhone)) {
      return new Response(
        JSON.stringify({ error: 'Invalid Spanish phone number format' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Normalize phone to E.164 format (+34...)
    let normalizedPhone = cleanedPhone
    if (!normalizedPhone.startsWith('+')) {
      if (normalizedPhone.startsWith('0034')) {
        normalizedPhone = '+' + normalizedPhone.substring(2)
      } else if (normalizedPhone.startsWith('34')) {
        normalizedPhone = '+' + normalizedPhone
      } else {
        normalizedPhone = '+34' + normalizedPhone
      }
    }

    // Check for recent verification attempts (rate limiting)
    const oneMinuteAgo = new Date(Date.now() - 60 * 1000).toISOString()
    const { data: recentCodes } = await supabase
      .from('verification_codes')
      .select('*')
      .eq('user_id', user.id)
      .eq('phone', normalizedPhone)
      .gte('created_at', oneMinuteAgo)

    if (recentCodes && recentCodes.length > 0) {
      return new Response(
        JSON.stringify({ error: 'Please wait before requesting another code' }),
        { status: 429, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Generate verification code
    const code = generateCode()

    // Store in database with 10-minute expiration
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString()

    const { error: dbError } = await supabase
      .from('verification_codes')
      .insert({
        user_id: user.id,
        phone: normalizedPhone,
        code: code,
        expires_at: expiresAt,
        attempts: 0,
        verified: false,
      })

    if (dbError) {
      console.error('Database error:', dbError)
      return new Response(
        JSON.stringify({ error: 'Failed to create verification code' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Send SMS via Twilio
    const smsSent = await sendSMS(normalizedPhone, code)

    if (!smsSent) {
      return new Response(
        JSON.stringify({ error: 'Failed to send SMS' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Verification code sent successfully',
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})

// Supabase Edge Function to verify SMS codes
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

interface VerifyRequest {
  phone: string
  code: string
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
    const { phone, code }: VerifyRequest = await req.json()

    if (!phone || phone.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'Phone number is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    if (!code || code.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'Verification code is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Normalize phone to E.164 format (+34...)
    const phoneRegex = /^(\+34|0034)?[6-9]\d{8}$/
    const cleanedPhone = phone.replace(/\s+/g, '')
    if (!phoneRegex.test(cleanedPhone)) {
      return new Response(
        JSON.stringify({ error: 'Invalid Spanish phone number format' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

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

    // Find the most recent unverified code for this user and phone
    const { data: verificationCodes, error: fetchError } = await supabase
      .from('verification_codes')
      .select('*')
      .eq('user_id', user.id)
      .eq('phone', normalizedPhone)
      .eq('verified', false)
      .order('created_at', { ascending: false })
      .limit(1)

    if (fetchError || !verificationCodes || verificationCodes.length === 0) {
      return new Response(
        JSON.stringify({ error: 'No verification code found for this phone number' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const verificationRecord = verificationCodes[0]

    // Check if code has expired
    const now = new Date()
    const expiresAt = new Date(verificationRecord.expires_at)
    if (now > expiresAt) {
      return new Response(
        JSON.stringify({ error: 'Verification code has expired' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Check attempts (max 5)
    if (verificationRecord.attempts >= 5) {
      return new Response(
        JSON.stringify({ error: 'Too many failed attempts. Please request a new code.' }),
        { status: 429, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Check if code matches
    if (verificationRecord.code !== code.trim()) {
      // Increment attempts
      await supabase
        .from('verification_codes')
        .update({ attempts: verificationRecord.attempts + 1 })
        .eq('id', verificationRecord.id)

      return new Response(
        JSON.stringify({
          error: 'Invalid verification code',
          attemptsRemaining: 5 - (verificationRecord.attempts + 1),
        }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Code is valid! Mark as verified
    const { error: updateCodeError } = await supabase
      .from('verification_codes')
      .update({ verified: true })
      .eq('id', verificationRecord.id)

    if (updateCodeError) {
      console.error('Error updating verification code:', updateCodeError)
      return new Response(
        JSON.stringify({ error: 'Failed to verify code' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Update profile to mark phone as verified
    const { error: updateProfileError } = await supabase
      .from('profiles')
      .update({
        phone: normalizedPhone,
        phone_verified: true,
      })
      .eq('id', user.id)

    if (updateProfileError) {
      console.error('Error updating profile:', updateProfileError)
      return new Response(
        JSON.stringify({ error: 'Failed to update profile' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Phone number verified successfully',
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

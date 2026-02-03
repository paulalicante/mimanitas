// Supabase Edge Function: notify-new-application
// Triggered by database webhook on applications INSERT.
// Notifies the job poster (seeker) via their preferred external channels.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID')
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN')
const TWILIO_PHONE_NUMBER = Deno.env.get('TWILIO_PHONE_NUMBER')
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
const REQUIRE_PREMIUM = Deno.env.get('REQUIRE_PREMIUM_NOTIFICATIONS') === 'true'
const WA_TEMPLATE_NEW_APPLICATION = Deno.env.get('WA_TEMPLATE_NEW_APPLICATION')

// Check if a user has premium access for external notifications
function isPremium(subscriptionStatus: string | null): boolean {
  if (!REQUIRE_PREMIUM) return true // Gate open — everyone gets external notifications
  return subscriptionStatus === 'free_trial' || subscriptionStatus === 'active'
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// --- Twilio helpers ---

async function sendSMS(to: string, body: string): Promise<boolean> {
  if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_PHONE_NUMBER) {
    console.error('Twilio env vars not set')
    return false
  }
  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`
  const auth = btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`)

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({ To: to, From: TWILIO_PHONE_NUMBER!, Body: body }).toString(),
  })
  if (!res.ok) {
    console.error('Twilio SMS error:', await res.text())
    return false
  }
  return true
}

async function sendWhatsApp(to: string, contentSid: string, contentVariables: Record<string, string>): Promise<boolean> {
  if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_PHONE_NUMBER) {
    console.error('Twilio env vars not set')
    return false
  }
  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`
  const auth = btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`)

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      To: `whatsapp:${to}`,
      From: `whatsapp:${TWILIO_PHONE_NUMBER!}`,
      ContentSid: contentSid,
      ContentVariables: JSON.stringify(contentVariables),
    }).toString(),
  })
  if (!res.ok) {
    console.error('Twilio WhatsApp error:', await res.text())
    return false
  }
  return true
}

async function sendEmail(to: string, subject: string, html: string): Promise<boolean> {
  if (!RESEND_API_KEY) {
    console.error('RESEND_API_KEY not set')
    return false
  }
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Mi Manitas <noreply@mimanitas.me>',
      to: [to],
      subject,
      html,
    }),
  })
  if (!res.ok) {
    console.error('Resend email error:', await res.text())
    return false
  }
  return true
}

// --- Main handler ---

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Payload from database webhook
    const payload = await req.json()
    const application = payload.record ?? payload
    const applicationId = application.id as string
    const jobId = application.job_id as string
    const applicantId = application.applicant_id as string

    console.log(`notify-new-application: app=${applicationId}, job=${jobId}, applicant=${applicantId}`)

    // Admin client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Get the job to find the poster
    const { data: job, error: jobError } = await supabase
      .from('jobs')
      .select('id, title, poster_id, price_amount, price_type, barrio')
      .eq('id', jobId)
      .single()

    if (jobError || !job) {
      console.error('Job not found:', jobError)
      return new Response(JSON.stringify({ error: 'job not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const posterId = job.poster_id as string

    // Get poster's notification preferences
    const { data: pref, error: prefError } = await supabase
      .from('notification_preferences')
      .select('sms_enabled, email_enabled, whatsapp_enabled')
      .eq('user_id', posterId)
      .maybeSingle()

    if (prefError) {
      console.error('Error loading preferences:', prefError)
    }

    // If no external channels enabled, nothing to do
    if (!pref || (!pref.sms_enabled && !pref.email_enabled && !pref.whatsapp_enabled)) {
      console.log('Poster has no external notifications enabled')
      return new Response(JSON.stringify({ notified: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get poster's profile (phone + subscription status)
    const { data: posterProfile } = await supabase
      .from('profiles')
      .select('name, phone, phone_verified, subscription_status')
      .eq('id', posterId)
      .single()

    // Premium check: poster must be premium to receive external notifications
    if (!isPremium(posterProfile?.subscription_status as string | null)) {
      console.log(`Poster ${posterId} is not premium, skipping external notifications`)
      return new Response(JSON.stringify({ skipped: true, reason: 'poster_not_premium' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get poster's email from auth
    const { data: { user: posterAuth } } = await supabase.auth.admin.getUserById(posterId)
    const posterEmail = posterAuth?.email

    // Get applicant name
    const { data: applicantProfile } = await supabase
      .from('profiles')
      .select('name')
      .eq('id', applicantId)
      .single()

    const applicantName = applicantProfile?.name || 'Alguien'
    const jobTitle = job.title || 'tu trabajo'

    // Build messages
    const smsBody = `Mi Manitas: ${applicantName} ha aplicado a tu trabajo "${jobTitle}". Abre la app para revisar su solicitud.`

    const emailSubject = `Nueva solicitud: ${applicantName} quiere ayudarte`
    const emailHtml = `
      <div style="font-family: sans-serif; max-width: 500px; margin: 0 auto;">
        <h2 style="color: #E86A33;">Nueva solicitud recibida</h2>
        <p><strong>${applicantName}</strong> ha aplicado a tu trabajo:</p>
        <h3>${jobTitle}</h3>
        <p style="margin-top: 24px;">
          <a href="https://mimanitas.me" style="background: #E86A33; color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px;">
            Ver solicitud
          </a>
        </p>
        <p style="color: #999; font-size: 12px; margin-top: 32px;">
          Recibes este email porque tienes las notificaciones por email activadas en Mi Manitas.
          Puedes desactivarlas en la app → Notificaciones.
        </p>
      </div>
    `

    // Send notifications
    let sent = 0
    const errors: string[] = []

    const phone = posterProfile?.phone as string | null
    const phoneVerified = posterProfile?.phone_verified === true

    // SMS
    if (pref.sms_enabled && phone && phoneVerified) {
      const ok = await sendSMS(phone, smsBody)
      if (ok) sent++
      else errors.push('SMS failed')
    }

    // WhatsApp (uses Content Template)
    if (pref.whatsapp_enabled && phone && phoneVerified && WA_TEMPLATE_NEW_APPLICATION) {
      const ok = await sendWhatsApp(phone, WA_TEMPLATE_NEW_APPLICATION, {
        '1': applicantName,
        '2': jobTitle,
      })
      if (ok) sent++
      else errors.push('WhatsApp failed')
    }

    // Email
    if (pref.email_enabled && posterEmail) {
      const ok = await sendEmail(posterEmail, emailSubject, emailHtml)
      if (ok) sent++
      else errors.push('Email failed')
    }

    console.log(`Notifications sent to poster: ${sent}, errors: ${errors.length}`)

    return new Response(
      JSON.stringify({ notified: sent, errors: errors.length }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

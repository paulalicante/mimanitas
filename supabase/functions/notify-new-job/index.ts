// Supabase Edge Function: notify-new-job
// Triggered by database webhook on jobs INSERT.
// Finds helpers with matching notification preferences and sends
// external notifications (SMS / WhatsApp / email).
// Includes smart matching: distance (via Google Distance Matrix), skills, availability.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID')
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN')
const TWILIO_PHONE_NUMBER = Deno.env.get('TWILIO_PHONE_NUMBER')
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
const REQUIRE_PREMIUM = Deno.env.get('REQUIRE_PREMIUM_NOTIFICATIONS') === 'true'
const WA_TEMPLATE_NEW_JOB = Deno.env.get('WA_TEMPLATE_NEW_JOB')
const GOOGLE_MAPS_API_KEY = Deno.env.get('GOOGLE_MAPS_API_KEY')

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

// --- Haversine + Distance Matrix helpers ---

// Haversine distance in km (straight-line)
function haversineDistanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371.0 // Earth radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

// Average urban speeds for Haversine time estimate (km/h)
const URBAN_SPEEDS: Record<string, number> = {
  'car': 30,
  'bike': 12,
  'walk': 5,
  'transit': 20,
  'escooter': 15,
}

// Buffer multipliers: how much longer real routes are vs straight line.
// Transit gets a very generous buffer because bus/tram routes are far from direct.
const ROUTE_BUFFER: Record<string, number> = {
  'car': 1.5,
  'bike': 1.5,
  'walk': 1.8,
  'transit': 2.5,
  'escooter': 1.5,
}

// Estimate travel minutes from Haversine distance (straight-line, no buffer)
function estimateTravelMinutes(distanceKm: number, mode: string): number {
  const speed = URBAN_SPEEDS[mode] ?? 15
  return (distanceKm / speed) * 60
}

// Google API transport mode mapping
function toGoogleMode(mode: string): string | null {
  const map: Record<string, string> = {
    'car': 'driving',
    'bike': 'bicycling',
    'walk': 'walking',
    'transit': 'transit',
    'escooter': 'bicycling', // closest approximation
  }
  return map[mode] ?? null
}

// Query Google Distance Matrix API for travel times
// Returns map of origin index -> duration in seconds (null if unreachable)
async function getDistanceMatrix(
  origins: string[],
  destination: string,
  mode: string
): Promise<Map<number, number | null>> {
  const results = new Map<number, number | null>()
  if (!GOOGLE_MAPS_API_KEY || origins.length === 0) return results

  const googleMode = toGoogleMode(mode)
  if (!googleMode) return results

  // Google Distance Matrix allows up to 25 origins per request
  const batchSize = 25
  for (let i = 0; i < origins.length; i += batchSize) {
    const batch = origins.slice(i, i + batchSize)
    const params = new URLSearchParams({
      origins: batch.join('|'),
      destinations: destination,
      mode: googleMode,
      key: GOOGLE_MAPS_API_KEY,
      language: 'es',
    })

    try {
      const res = await fetch(
        `https://maps.googleapis.com/maps/api/distancematrix/json?${params}`
      )
      const data = await res.json()

      if (data.rows) {
        for (let j = 0; j < data.rows.length; j++) {
          const element = data.rows[j].elements[0]
          results.set(
            i + j,
            element.status === 'OK' ? element.duration.value : null
          )
        }
      }
    } catch (e) {
      console.error(`Distance Matrix API error (mode=${mode}, batch=${i}):`, e)
    }
  }

  return results
}

// --- Main handler ---

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // This function is called by a Supabase Database Webhook.
    // The payload contains the new job record.
    const payload = await req.json()

    // Database webhook sends { type, table, record, schema, old_record }
    const job = payload.record ?? payload
    const jobId = job.id as string
    const posterId = job.poster_id as string
    const title = job.title as string || 'Nuevo trabajo'
    const skillId = job.skill_id as string | null
    const barrio = job.barrio as string | null
    const priceAmount = job.price_amount ? Number(job.price_amount) : null
    const priceType = job.price_type as string | null
    const locationAddress = job.location_address as string | null

    // Smart matching fields
    const jobLat = job.location_lat ? Number(job.location_lat) : null
    const jobLng = job.location_lng ? Number(job.location_lng) : null
    const scheduledDate = job.scheduled_date as string | null // 'YYYY-MM-DD'
    const scheduledTime = job.scheduled_time as string | null // 'HH:MM:SS'
    const isFlexible = job.is_flexible === true

    console.log(`notify-new-job: job=${jobId}, title="${title}", skill=${skillId}, barrio=${barrio}, price=${priceAmount}, lat=${jobLat}, lng=${jobLng}, date=${scheduledDate}, time=${scheduledTime}, flexible=${isFlexible}`)

    // Only notify for open jobs
    if (job.status !== 'open') {
      return new Response(JSON.stringify({ skipped: true, reason: 'not open' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Admin client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Premium check: poster must be premium for their jobs to be broadcast externally
    const { data: posterProfile } = await supabase
      .from('profiles')
      .select('subscription_status')
      .eq('id', posterId)
      .single()

    if (!isPremium(posterProfile?.subscription_status)) {
      console.log(`Poster ${posterId} is not premium, skipping external notifications`)
      return new Response(JSON.stringify({ skipped: true, reason: 'poster_not_premium' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Find helpers with at least one external channel enabled
    // Include new smart matching columns
    const { data: prefs, error: prefsError } = await supabase
      .from('notification_preferences')
      .select(`
        user_id,
        sms_enabled,
        email_enabled,
        whatsapp_enabled,
        notify_skills,
        min_price_amount,
        min_hourly_rate,
        transport_modes,
        max_travel_minutes
      `)
      .or('sms_enabled.eq.true,email_enabled.eq.true,whatsapp_enabled.eq.true')
      .or('paused.eq.false,paused.is.null')

    if (prefsError) {
      console.error('Error querying preferences:', prefsError)
      return new Response(JSON.stringify({ error: 'db error' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!prefs || prefs.length === 0) {
      console.log('No helpers with external notifications enabled')
      return new Response(JSON.stringify({ notified: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // --- Pass 1: Skill / Price filters ---
    const matchingUserIds: string[] = []

    for (const pref of prefs) {
      // Skip the job poster
      if (pref.user_id === posterId) continue

      // Skill filter (empty array = all skills)
      const prefSkills: string[] = pref.notify_skills ?? []
      if (prefSkills.length > 0 && skillId && !prefSkills.includes(skillId)) continue

      // Min price filter (checks price_type)
      if (priceAmount != null) {
        if (priceType === 'hourly') {
          const minHourly = pref.min_hourly_rate ? Number(pref.min_hourly_rate) : null
          if (minHourly != null && priceAmount < minHourly) continue
        } else {
          const minPrice = pref.min_price_amount ? Number(pref.min_price_amount) : null
          if (minPrice != null && priceAmount < minPrice) continue
        }
      }

      matchingUserIds.push(pref.user_id)
    }

    console.log(`After skill/price filter: ${matchingUserIds.length} of ${prefs.length}`)

    if (matchingUserIds.length === 0) {
      return new Response(JSON.stringify({ notified: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // --- Pass 2: Distance filter (Haversine pre-filter + Google API for borderline) ---

    // Load helper profiles WITH location
    const { data: profiles, error: profError } = await supabase
      .from('profiles')
      .select('id, name, phone, phone_verified, user_type, subscription_status, location_lat, location_lng')
      .in('id', matchingUserIds)
      .eq('user_type', 'helper')

    if (profError || !profiles) {
      console.error('Error loading profiles:', profError)
      return new Response(JSON.stringify({ error: 'profile query error' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Build preference lookup
    const prefMap = new Map(prefs.map(p => [p.user_id, p]))

    let filteredProfiles = profiles

    if (jobLat != null && jobLng != null) {
      const jobDestination = `${jobLat},${jobLng}`

      // Separate helpers: those with location+transport vs those without
      const helpersWithLocation: typeof profiles = []
      const helpersWithoutLocation: typeof profiles = []

      for (const p of profiles) {
        const pref = prefMap.get(p.id)
        const transportModes: string[] = pref?.transport_modes ?? []
        const hasLocation = p.location_lat != null && p.location_lng != null

        if (hasLocation && transportModes.length > 0) {
          helpersWithLocation.push(p)
        } else {
          helpersWithoutLocation.push(p)
        }
      }

      console.log(`Distance filter: ${helpersWithLocation.length} with location, ${helpersWithoutLocation.length} without`)

      if (helpersWithLocation.length > 0) {
        // --- Haversine pre-filter: categorize each helper ---
        const passedDirectly = new Set<string>()        // clearly within range
        const borderlineHelpers: { profile: typeof profiles[0], mode: string, origin: string, maxMinutes: number }[] = []
        const rejectedDirectly = new Set<string>()      // clearly out of range

        for (const p of helpersWithLocation) {
          const pref = prefMap.get(p.id)!
          const transportModes: string[] = pref.transport_modes ?? []
          const maxMinutes = pref.max_travel_minutes ?? 30
          const helperLat = Number(p.location_lat)
          const helperLng = Number(p.location_lng)

          const distKm = haversineDistanceKm(helperLat, helperLng, jobLat, jobLng)

          // Find the fastest mode for this helper
          let bestMinutes = Infinity
          let bestMode = transportModes[0] || 'car'
          let bestBuffer = ROUTE_BUFFER[bestMode] ?? 1.5

          for (const mode of transportModes) {
            const mins = estimateTravelMinutes(distKm, mode)
            if (mins < bestMinutes) {
              bestMinutes = mins
              bestMode = mode
              bestBuffer = ROUTE_BUFFER[mode] ?? 1.5
            }
          }

          // Three-bucket classification:
          // 1) Clear pass: Haversine estimate < 50% of max → definitely within range
          // 2) Clear fail: Haversine estimate > buffer * max → definitely out of range
          // 3) Borderline: between 50% and buffer * max → need Google API
          const clearPassThreshold = maxMinutes * 0.5
          const clearFailThreshold = maxMinutes * bestBuffer

          if (bestMinutes <= clearPassThreshold) {
            console.log(`Helper ${p.id}: Haversine ${bestMinutes.toFixed(0)}min via ${bestMode} << ${maxMinutes}min max → PASS (no API)`)
            passedDirectly.add(p.id)
          } else if (bestMinutes > clearFailThreshold) {
            console.log(`Helper ${p.id}: Haversine ${bestMinutes.toFixed(0)}min via ${bestMode} >> ${maxMinutes}min max (buffer ${bestBuffer}x) → REJECT (no API)`)
            rejectedDirectly.add(p.id)
          } else {
            console.log(`Helper ${p.id}: Haversine ${bestMinutes.toFixed(0)}min via ${bestMode}, max=${maxMinutes}min (buffer ${bestBuffer}x) → BORDERLINE (needs API)`)
            borderlineHelpers.push({
              profile: p,
              mode: bestMode,
              origin: `${helperLat},${helperLng}`,
              maxMinutes,
            })
          }
        }

        console.log(`Haversine pre-filter: ${passedDirectly.size} passed, ${rejectedDirectly.size} rejected, ${borderlineHelpers.length} borderline`)

        // --- Google API only for borderline helpers ---
        const passedAPI = new Set<string>()

        if (borderlineHelpers.length > 0 && GOOGLE_MAPS_API_KEY) {
          // Group borderline helpers by transport mode for efficient batching
          const modeGroups = new Map<string, typeof borderlineHelpers>()
          for (const h of borderlineHelpers) {
            if (!modeGroups.has(h.mode)) modeGroups.set(h.mode, [])
            modeGroups.get(h.mode)!.push(h)
          }

          for (const [mode, group] of modeGroups) {
            const origins = group.map(g => g.origin)
            console.log(`API check: ${origins.length} borderline helpers via ${mode}`)

            const durations = await getDistanceMatrix(origins, jobDestination, mode)

            for (let i = 0; i < group.length; i++) {
              const durationSeconds = durations.get(i)
              const maxSeconds = group[i].maxMinutes * 60

              if (durationSeconds == null) {
                // API couldn't calculate route — let helper through (graceful fallback)
                console.log(`Helper ${group[i].profile.id}: no route via ${mode}, allowing through`)
                passedAPI.add(group[i].profile.id)
              } else if (durationSeconds <= maxSeconds) {
                const mins = Math.round(durationSeconds / 60)
                console.log(`Helper ${group[i].profile.id}: API ${mins}min via ${mode} <= ${group[i].maxMinutes}min max ✓`)
                passedAPI.add(group[i].profile.id)
              } else {
                const mins = Math.round(durationSeconds / 60)
                console.log(`Helper ${group[i].profile.id}: API ${mins}min via ${mode} > ${group[i].maxMinutes}min max ✗`)
              }
            }
          }
        } else if (borderlineHelpers.length > 0 && !GOOGLE_MAPS_API_KEY) {
          // No API key — let all borderline helpers through
          console.log('No GOOGLE_MAPS_API_KEY, letting all borderline helpers through')
          for (const h of borderlineHelpers) {
            passedAPI.add(h.profile.id)
          }
        }

        // Combine: direct passes + API passes + helpers without location
        filteredProfiles = [
          ...helpersWithLocation.filter(p => passedDirectly.has(p.id) || passedAPI.has(p.id)),
          ...helpersWithoutLocation,
        ]

        console.log(`After distance filter: ${filteredProfiles.length} helpers remain (${passedDirectly.size} Haversine pass, ${passedAPI.size} API pass, ${helpersWithoutLocation.length} no location)`)
      }
    } else {
      console.log('Job has no lat/lng, skipping distance filter')
    }

    // --- Pass 3: Availability filter (if job has scheduled date and is NOT flexible) ---

    if (scheduledDate && !isFlexible && filteredProfiles.length > 0) {
      console.log(`Checking availability for ${filteredProfiles.length} helpers (date=${scheduledDate}, time=${scheduledTime ?? 'not set'})`)

      // Parse scheduled date to get day of week (0=Sun, 1=Mon, ..., 6=Sat)
      const dateObj = new Date(scheduledDate + 'T00:00:00')
      const dayOfWeek = dateObj.getDay() // 0=Sun, 1=Mon, ..., 6=Sat

      // Parse job time for comparison (HH:MM:SS format) — may be null
      let jobTimeMinutes: number | null = null
      if (scheduledTime) {
        const jobTimeParts = scheduledTime.split(':')
        jobTimeMinutes = parseInt(jobTimeParts[0]) * 60 + parseInt(jobTimeParts[1])
      }

      // Get all availability records for these helpers
      const helperIds = filteredProfiles.map(p => p.id)

      const { data: availability, error: availError } = await supabase
        .from('availability')
        .select('user_id, day_of_week, start_time, end_time, is_recurring, specific_date')
        .in('user_id', helperIds)

      if (availError) {
        console.error('Error loading availability:', availError)
        // On error, don't filter — let all helpers through
      } else if (availability) {
        // Build availability map: user_id -> list of slots
        const availMap = new Map<string, typeof availability>()
        for (const row of availability) {
          if (!availMap.has(row.user_id)) availMap.set(row.user_id, [])
          availMap.get(row.user_id)!.push(row)
        }

        const passedAvailability: typeof filteredProfiles = []

        for (const profile of filteredProfiles) {
          const slots = availMap.get(profile.id)

          // No availability records → treat as "always available"
          if (!slots || slots.length === 0) {
            passedAvailability.push(profile)
            continue
          }

          // Check if any slot matches the job's day (and time if set)
          let matches = false
          for (const slot of slots) {
            // Check specific date match first
            if (slot.specific_date === scheduledDate) {
              if (jobTimeMinutes == null) {
                // No time specified — day match is enough
                matches = true
                break
              }
              const startParts = (slot.start_time as string).split(':')
              const endParts = (slot.end_time as string).split(':')
              const startMinutes = parseInt(startParts[0]) * 60 + parseInt(startParts[1])
              const endMinutes = parseInt(endParts[0]) * 60 + parseInt(endParts[1])

              if (jobTimeMinutes >= startMinutes && jobTimeMinutes <= endMinutes) {
                matches = true
                break
              }
            }

            // Check recurring day match
            if (slot.is_recurring && slot.day_of_week === dayOfWeek) {
              if (jobTimeMinutes == null) {
                // No time specified — day match is enough
                matches = true
                break
              }
              const startParts = (slot.start_time as string).split(':')
              const endParts = (slot.end_time as string).split(':')
              const startMinutes = parseInt(startParts[0]) * 60 + parseInt(startParts[1])
              const endMinutes = parseInt(endParts[0]) * 60 + parseInt(endParts[1])

              if (jobTimeMinutes >= startMinutes && jobTimeMinutes <= endMinutes) {
                matches = true
                break
              }
            }
          }

          if (matches) {
            passedAvailability.push(profile)
          } else {
            console.log(`Helper ${profile.id}: no availability match for ${scheduledDate} ${scheduledTime ?? '(no time)'}`)
          }
        }

        filteredProfiles = passedAvailability
        console.log(`After availability filter: ${filteredProfiles.length} helpers remain`)
      }
    } else {
      if (isFlexible) console.log('Job is flexible, skipping availability filter')
      else if (!scheduledDate) console.log('Job has no scheduled date, skipping availability filter')
    }

    // --- Send notifications to filtered helpers ---

    if (filteredProfiles.length === 0) {
      console.log('No helpers passed all filters')
      return new Response(JSON.stringify({ notified: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get emails from auth.users
    const { data: authUsers, error: authError } = await supabase.auth.admin.listUsers()
    const emailMap = new Map<string, string>()
    if (!authError && authUsers?.users) {
      for (const u of authUsers.users) {
        if (u.email) emailMap.set(u.id, u.email)
      }
    }

    // Build notification message
    const priceLine = priceAmount
      ? `${priceAmount}€${priceType === 'hourly' ? '/h' : ''}`
      : 'Precio a negociar'
    const locationLine = barrio || locationAddress || ''

    const smsBody = `Mi Manitas: Nuevo trabajo "${title}" ${locationLine ? 'en ' + locationLine : ''} — ${priceLine}. Abre la app para ver detalles.`

    const emailSubject = `Nuevo trabajo: ${title}`
    const emailHtml = `
      <div style="font-family: sans-serif; max-width: 500px; margin: 0 auto;">
        <h2 style="color: #E86A33;">Nuevo trabajo disponible</h2>
        <h3>${title}</h3>
        <p><strong>Precio:</strong> ${priceLine}</p>
        ${locationLine ? `<p><strong>Zona:</strong> ${locationLine}</p>` : ''}
        <p style="margin-top: 24px;">
          <a href="https://mimanitas.me" style="background: #E86A33; color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px;">
            Ver trabajo
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

    for (const profile of filteredProfiles) {
      const userPref = prefMap.get(profile.id)
      if (!userPref) continue

      // Premium check: helper must be premium to receive external notifications
      if (!isPremium(profile.subscription_status as string | null)) {
        console.log(`Helper ${profile.id} is not premium, skipping external notification`)
        continue
      }

      const phone = profile.phone as string | null
      const email = emailMap.get(profile.id)
      const phoneVerified = profile.phone_verified === true

      // SMS
      if (userPref.sms_enabled && phone && phoneVerified) {
        const ok = await sendSMS(phone, smsBody)
        if (ok) sent++
        else errors.push(`SMS failed for ${profile.id}`)
      }

      // WhatsApp (same phone number, uses Content Template)
      if (userPref.whatsapp_enabled && phone && phoneVerified && WA_TEMPLATE_NEW_JOB) {
        const ok = await sendWhatsApp(phone, WA_TEMPLATE_NEW_JOB, {
          '1': title,
          '2': locationLine ? 'en ' + locationLine : '',
          '3': priceLine,
        })
        if (ok) sent++
        else errors.push(`WhatsApp failed for ${profile.id}`)
      }

      // Email
      if (userPref.email_enabled && email) {
        const ok = await sendEmail(email, emailSubject, emailHtml)
        if (ok) sent++
        else errors.push(`Email failed for ${profile.id}`)
      }
    }

    console.log(`Notifications sent: ${sent}, errors: ${errors.length}`)
    if (errors.length > 0) console.error('Send errors:', errors)

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

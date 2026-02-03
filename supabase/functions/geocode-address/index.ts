// Supabase Edge Function: geocode-address
// Server-side proxy to Google Maps APIs.
// Hides the API key and avoids CORS issues for Flutter Web.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

const GOOGLE_MAPS_API_KEY = Deno.env.get('GOOGLE_MAPS_API_KEY')

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Alicante center coordinates for biasing results
const ALICANTE_LAT = 38.3452
const ALICANTE_LNG = -0.4815

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (!GOOGLE_MAPS_API_KEY) {
    return new Response(
      JSON.stringify({ error: 'GOOGLE_MAPS_API_KEY not configured' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  try {
    const body = await req.json()
    const action = body.action as string

    if (action === 'autocomplete') {
      return await handleAutocomplete(body.input as string, body.sessionToken as string | undefined)
    } else if (action === 'details') {
      return await handleDetails(body.placeId as string)
    } else if (action === 'distance_matrix') {
      return await handleDistanceMatrix(
        body.origins as string[],
        body.destination as string,
        body.mode as string
      )
    } else {
      return new Response(
        JSON.stringify({ error: `Unknown action: ${action}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
  } catch (error) {
    console.error('geocode-address error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function handleAutocomplete(input: string, sessionToken?: string) {
  if (!input || input.length < 2) {
    return new Response(
      JSON.stringify({ predictions: [] }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  const params = new URLSearchParams({
    input,
    key: GOOGLE_MAPS_API_KEY!,
    components: 'country:es',
    location: `${ALICANTE_LAT},${ALICANTE_LNG}`,
    radius: '50000', // 50km radius bias around Alicante
    language: 'es',
  })
  if (sessionToken) params.set('sessiontoken', sessionToken)

  const res = await fetch(
    `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params}`
  )
  const data = await res.json()

  // Return simplified predictions
  const predictions = (data.predictions || []).map((p: any) => ({
    placeId: p.place_id,
    description: p.description,
    mainText: p.structured_formatting?.main_text || '',
    secondaryText: p.structured_formatting?.secondary_text || '',
  }))

  return new Response(
    JSON.stringify({ predictions }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

async function handleDetails(placeId: string) {
  if (!placeId) {
    return new Response(
      JSON.stringify({ error: 'placeId required' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  const params = new URLSearchParams({
    place_id: placeId,
    key: GOOGLE_MAPS_API_KEY!,
    fields: 'geometry,formatted_address,address_components',
    language: 'es',
  })

  const res = await fetch(
    `https://maps.googleapis.com/maps/api/place/details/json?${params}`
  )
  const data = await res.json()
  const result = data.result

  if (!result) {
    return new Response(
      JSON.stringify({ error: 'Place not found' }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  // Extract barrio from address components
  let barrio: string | null = null
  for (const comp of result.address_components || []) {
    const types: string[] = comp.types || []
    if (types.includes('sublocality') || types.includes('sublocality_level_1')) {
      barrio = comp.long_name
      break
    }
    if (types.includes('locality')) {
      barrio = comp.long_name
    }
  }

  return new Response(
    JSON.stringify({
      lat: result.geometry?.location?.lat,
      lng: result.geometry?.location?.lng,
      address: result.formatted_address,
      barrio,
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

async function handleDistanceMatrix(origins: string[], destination: string, mode: string) {
  if (!origins?.length || !destination) {
    return new Response(
      JSON.stringify({ error: 'origins and destination required' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  // Google API mode mapping
  const googleMode = mode === 'escooter' ? 'bicycling' : mode
  const validModes = ['driving', 'walking', 'bicycling', 'transit']
  if (!validModes.includes(googleMode)) {
    return new Response(
      JSON.stringify({ error: `Invalid mode: ${mode}` }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  // Google Distance Matrix allows up to 25 origins per request
  const batchSize = 25
  const allResults: Array<{ index: number, durationSeconds: number | null, status: string }> = []

  for (let i = 0; i < origins.length; i += batchSize) {
    const batch = origins.slice(i, i + batchSize)
    const params = new URLSearchParams({
      origins: batch.join('|'),
      destinations: destination,
      mode: googleMode,
      key: GOOGLE_MAPS_API_KEY!,
      language: 'es',
    })

    const url = `https://maps.googleapis.com/maps/api/distancematrix/json?${params}`

    const res = await fetch(url)
    const data = await res.json()

    // If Google returns a top-level error, return it to the client
    if (data.status !== 'OK') {
      return new Response(
        JSON.stringify({
          results: [],
          googleStatus: data.status,
          googleError: data.error_message || null,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (data.rows) {
      for (let j = 0; j < data.rows.length; j++) {
        const element = data.rows[j].elements[0]
        allResults.push({
          index: i + j,
          durationSeconds: element.status === 'OK' ? element.duration.value : null,
          status: element.status,
        })
      }
    }
  }

  return new Response(
    JSON.stringify({ results: allResults }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

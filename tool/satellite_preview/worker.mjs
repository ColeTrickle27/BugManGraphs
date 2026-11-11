const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
});

export async function searchAddress(request, fetcher = fetch) {
  if (request.method !== 'GET') return json({error: 'Use GET for address search.'}, 405);
  const address = new URL(request.url).searchParams.get('address')?.trim();
  if (!address || address.length < 3 || address.length > 300) {
    return json({error: 'Enter a complete North Carolina street address.'}, 400);
  }
  const endpoint = new URL('https://geocoding.geo.census.gov/geocoder/locations/onelineaddress');
  endpoint.search = new URLSearchParams({address, benchmark: 'Public_AR_Current', format: 'json'}).toString();
  try {
    const response = await fetcher(endpoint.toString(), {signal: AbortSignal.timeout(20000)});
    if (!response.ok) throw new Error('Geocoder unavailable');
    const payload = await response.json();
    const matches = (payload.result?.addressMatches ?? []).filter(match => {
      const {x, y} = match.coordinates ?? {};
      return match.addressComponents?.state === 'NC' && Number.isFinite(x) && Number.isFinite(y)
        && x >= -84.33 && x <= -75.40 && y >= 33.75 && y <= 36.60;
    }).slice(0, 5).map(match => ({address: match.matchedAddress,
      latitude: match.coordinates.y, longitude: match.coordinates.x}));
    return json({matches});
  } catch {
    return json({error: 'Address search is temporarily unavailable. Retry with a complete North Carolina address.'}, 503);
  }
}

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname === '/api/preview/address-search') return searchAddress(request);
    return env.ASSETS.fetch(request);
  }
};

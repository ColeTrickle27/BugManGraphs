// UNPUBLISHED prototype for the already employee-Access-protected /access-ready route.
// No server verifier reason is exposed; these are fixed public response classifications.
export const probeScript = `
const button = document.getElementById('check');
const result = document.getElementById('result');
button.addEventListener('click', async () => {
 if (button.disabled) return;
 button.disabled = true;
 result.textContent = 'Checking…';
 try {
  const response = await fetch('/api/me', {method:'GET',credentials:'same-origin',cache:'no-store',redirect:'manual',signal:AbortSignal.timeout(10000)});
  let code = 'unrecognized_response';
  const approved = new Map([
   ['Graph relay authentication is required.','transport_auth_required'],
   ['Sign in required.','application_signin_required'],
   ['Graph relay is temporarily unavailable.','transport_unavailable'],
   ['Request origin could not be verified.','origin_rejected'],
   ['Account drafts are unavailable.','relay_unavailable']
  ]);
  try {
   const body = await response.json();
   if (response.status === 200) code = body?.user && typeof body.user === 'object' && !Array.isArray(body.user) ? 'session_available' : 'unrecognized_response';
   else code = approved.get(body?.error) || 'unrecognized_response';
  } catch {}
  result.textContent = 'HTTP ' + response.status + ' · ' + code;
 } catch { result.textContent = 'HTTP unavailable · request_failed'; }
});
`;
export function onRequest({request,env}) {
 const url = new URL(request.url);
 if (url.origin !== 'https://graphs.holloman-ext.com' || url.pathname !== '/access-ready' || request.method !== 'GET' || url.search) return new Response('Not found',{status:404});
 const ready = env.GRAPH_DRAFTS_RELAY_ENABLED === 'true' && !!env.GRAPH_OPS_ACCESS_CLIENT_ID && !!env.GRAPH_OPS_ACCESS_CLIENT_SECRET;
 const nonce = crypto.randomUUID().replaceAll('-','');
 const html = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Graphs connection check</title><main><h1>Graphs connection check</h1><p>This checks your session once. It does not sync or create a graph. A server diagnostic capture must be coordinated separately.</p><button type="button" id="check" ${ready?'':'disabled'}>Check connection once</button><p role="status" id="result">${ready?'Ready to check':'Relay unavailable'}</p></main><script nonce="${nonce}">${probeScript}</script></html>`;
 return new Response(html,{status:ready?200:503,headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'private, no-store','Content-Security-Policy':`default-src 'none'; script-src 'nonce-${nonce}'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`,'X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'}});
}

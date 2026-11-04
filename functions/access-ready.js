export function onRequest({request,env}) {
  const url=new URL(request.url);
  if(url.origin!=='https://graphs.holloman-ext.com' || request.method!=='GET' || url.search) return new Response('Not found',{status:404});
  const ready=env.GRAPH_DRAFTS_RELAY_ENABLED==='true' && env.GRAPH_OPS_ACCESS_CLIENT_ID && env.GRAPH_OPS_ACCESS_CLIENT_SECRET;
  // This path must be protected by the independently approved human Access app.
  // It never redirects/reloads the original editor or exposes bindings/cookies.
  return new Response(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>BugMan Graphs employee access</title><body><main><h1>${ready?'Employee access page opened':'Employee access is not enabled'}</h1><p>If you completed employee sign-in, return to your original Graphs tab and retry sign-in or sync. Your open editor has not been changed.</p></main></body></html>`,{status:ready?200:503,headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'private, no-store','Content-Security-Policy':"default-src 'none'; style-src 'none'; frame-ancestors 'none'; base-uri 'none'",'X-Content-Type-Options':'nosniff'}});
}

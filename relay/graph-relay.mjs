// Fixed authority only. Never accept upstream hosts, tokens or cookie domains from input.
const UPSTREAM = 'https://ops.holloman-ext.com';
const ORIGIN = 'https://graphs.holloman-ext.com';
const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const SECURITY = {'Cache-Control':'private, no-store','Pragma':'no-cache','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; frame-ancestors 'none'"};
function fail(status, error) { return Response.json({error},{status,headers:SECURITY}); }
function route(url, method) {
  const p=url.pathname;
  if (['/api/login','/api/logout'].includes(p)) return method==='POST' && !url.search ? {cap:65536,auth:true} : null;
  if (p==='/api/me' || p==='/api/graph-drafts/context' || p==='/api/graph-drafts/authors') return method==='GET' && !url.search ? {draft:p.endsWith('/authors')} : null;
  if (p==='/api/graph-drafts' && method==='GET') {
    const keys=[...url.searchParams.keys()];
    if(keys.some(k=>!['limit','cursor'].includes(k)) || new Set(keys).size!==keys.length) return null;
    const limit=url.searchParams.get('limit');
    if(limit!==null && (!/^\d{1,3}$/.test(limit) || +limit<1 || +limit>300)) return null;
    return {draft:true};
  }
  if (/^\/api\/graph-drafts\/[A-Za-z0-9_-]{1,120}$/.test(p) && !['authors','context'].includes(p.split('/').at(-1)) && !url.search && ['GET','POST'].includes(method)) return {draft:true,cap:25*1024*1024};
  return null;
}
function cookie(request) {
  const parts=(request.headers.get('Cookie')||'').split(';').map(x=>x.trim()).filter(x=>x.startsWith('hob_session='));
  if(parts.length>1) throw new Error('Ambiguous session');
  if(!parts.length) return '';
  if(parts[0].length>8192 || !/^hob_session=[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(parts[0])) throw new Error('Invalid session');
  return parts[0];
}
function validCookie(value, logout) {
  const pieces=value.split(';').map(x=>x.trim());
  const attrs=new Map(pieces.slice(1).map(x=>{const i=x.indexOf('=');return i<0?[x.toLowerCase(),'']:[x.slice(0,i).trim().toLowerCase(),x.slice(i+1)];}));
  if(attrs.size!==pieces.length-1 || [...attrs.keys()].some(k=>!['secure','httponly','samesite','path','max-age','expires','priority'].includes(k))) return false;
  return (logout ? pieces[0]==='hob_session=' && attrs.get('max-age')==='0' : /^hob_session=[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(pieces[0])) && !attrs.has('domain') && attrs.get('path')==='/' && attrs.has('secure') && attrs.has('httponly') && attrs.get('samesite')?.toLowerCase()==='strict';
}
// origin/fetcher are injected only by isolated local fixtures, never by Pages bindings or requests.
export function createGraphRelay({origin=ORIGIN,fetcher=fetch,accessClientId,accessClientSecret}={}) {
  return async request => {
    const url=new URL(request.url), rule=route(url,request.method);
    if(url.origin!==origin || !rule) return fail(404,'Route unavailable.');
    const incoming=request.headers.get('Origin'), site=request.headers.get('Sec-Fetch-Site'), mode=request.headers.get('Sec-Fetch-Mode'), dest=request.headers.get('Sec-Fetch-Dest');
    if(site!=='same-origin' || !['cors','same-origin'].includes(mode) || dest!=='empty' || (incoming!==null && incoming!==origin) || (request.method==='POST' && incoming!==origin)) return fail(403,'Request origin could not be verified.');
    const expected=request.headers.get('X-Graph-Expected-Account-Id');
    if(rule.draft && !expected) return fail(428,'Account context is required.');
    if(rule.draft && !UUID.test(expected)) return fail(400,'Invalid account context.');
    if(request.method==='POST' && request.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase()!=='application/json') return fail(415,'JSON is required.');
    const size=request.headers.get('Content-Length');
    if(size!==null && (!/^\d+$/.test(size) || +size>(rule.cap||0))) return fail(413,'Request is too large.');
    let session;try {session=cookie(request);} catch {return fail(400,'Invalid session cookie.');}
    const headers=new Headers({'Accept':'application/json','Cache-Control':'no-store','Origin':UPSTREAM,'Sec-Fetch-Site':'same-origin','Sec-Fetch-Mode':'cors','Sec-Fetch-Dest':'empty'});
    if(accessClientId || accessClientSecret) {
      if(!accessClientId || !accessClientSecret) return fail(503,'Employee access is not configured. Recovery remains on this device.');
      headers.set('CF-Access-Client-Id',accessClientId);
      headers.set('CF-Access-Client-Secret',accessClientSecret);
    }
    if(session) headers.set('Cookie',session);
    if(rule.draft) headers.set('X-Graph-Expected-Account-Id',expected);
    let body, exceeded=false;
    if(request.method==='POST') {
      headers.set('Content-Type','application/json');let seen=0;
      body=request.body?.pipeThrough(new TransformStream({transform(chunk,controller){seen+=chunk.byteLength;if(seen>rule.cap) {exceeded=true;throw new Error('Request is too large');}controller.enqueue(chunk);}}));
    }
    let upstream;
    try {upstream=await fetcher(new Request(UPSTREAM+url.pathname+url.search,{method:request.method,headers,body,redirect:'manual',duplex:'half',cache:'no-store',signal:AbortSignal.timeout(60000)}));} catch {if(exceeded) return fail(413,'Request is too large.');return fail(503,'The account service is unavailable. Recovery remains on this device.');}
    if(upstream.status>=300 && upstream.status<400 || upstream.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase()!=='application/json') {await upstream.body?.cancel();return fail(502,'Unexpected account service response.');}
    const responseHeaders=new Headers({...SECURITY,'Content-Type':'application/json; charset=utf-8'});
    const cookies=(upstream.headers.getSetCookie ? upstream.headers.getSetCookie() : upstream.headers.getAll('Set-Cookie')).filter(value=>!/^CF_Authorization=/i.test(value.trim()));
    if(cookies.length) {
      if(!rule.auth || cookies.length!==1 || !validCookie(cookies[0],url.pathname==='/api/logout')) {await upstream.body?.cancel();return fail(502,'Unexpected account cookie.');}
      responseHeaders.append('Set-Cookie',cookies[0]);
    }
    const encoding=upstream.headers.get('Content-Encoding');
    if(encoding) responseHeaders.set('Content-Encoding',encoding);
    return new Response(upstream.body,{status:upstream.status,headers:responseHeaders,encodeBody:encoding?'manual':'automatic'});
  };
}

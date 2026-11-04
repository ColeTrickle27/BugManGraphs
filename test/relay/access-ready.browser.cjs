const {chromium}=require('playwright');
const http=require('node:http');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
// Requires an installed Playwright package and Chromium. Never uses a user profile.
const output=process.env.ACCESS_READY_TEST_OUTPUT || fs.mkdtempSync(path.join(os.tmpdir(),'access-ready-browser-'));
fs.mkdirSync(output,{recursive:true});
(async()=>{
 const {onRequest}=await import('../../functions/access-ready.js');
 const sentinel='SYNTHETIC_SENTINEL_NEVER_RENDER';
 let fixture,enabled=true,requests=[],redirectHits=0;
 const env={GRAPH_DRAFTS_RELAY_ENABLED:'true',GRAPH_OPS_ACCESS_CLIENT_ID:sentinel,GRAPH_OPS_ACCESS_CLIENT_SECRET:sentinel};
 const server=http.createServer(async(req,res)=>{
  if(req.url==='/access-ready'){
   const response=onRequest({request:new Request('https://graphs.holloman-ext.com/access-ready'),env:enabled?env:{}});
   res.writeHead(response.status,Object.fromEntries(response.headers));res.end(await response.text());return;
  }
  if(req.url==='/api/me'){
   let body='';for await(const chunk of req)body+=chunk;
   requests.push({url:req.url,method:req.method,body,mode:req.headers['sec-fetch-mode'],dest:req.headers['sec-fetch-dest'],site:req.headers['sec-fetch-site']});
   if(fixture.kind==='network'){req.socket.destroy();return;}
   if(fixture.kind==='timeout')return;
   if(fixture.kind==='redirect'){res.writeHead(302,{Location:'/redirect-target'});res.end();return;}
   res.writeHead(fixture.status,{'Content-Type':fixture.type||'application/json'});res.end(fixture.body);return;
  }
  if(req.url==='/redirect-target')redirectHits++;
  res.writeHead(404);res.end();
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const origin=`http://127.0.0.1:${server.address().port}`;
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE || '/usr/bin/chromium',headless:true});
 const results=[];
 try{
 const cases=[
 ['user',200,JSON.stringify({user:{id:sentinel},extra:sentinel}),'session_available'],
 ...[['Graph relay authentication is required.','transport_auth_required'],['Sign in required.','application_signin_required'],['Graph relay is temporarily unavailable.','transport_unavailable'],['Request origin could not be verified.','origin_rejected'],['Account drafts are unavailable.','relay_unavailable']].map(([error,code])=>[code,401,JSON.stringify({error,extra:sentinel}),code]),
 ['unknown',401,JSON.stringify({error:sentinel}),'unrecognized_response'],
 ['malformed',200,'{'+sentinel,'unrecognized_response'],
 ['html',200,'<html>'+sentinel+'</html>','unrecognized_response'],
 ['array-user',200,JSON.stringify({user:[sentinel]}),'unrecognized_response'],
 ['null-user',200,JSON.stringify({user:null}),'unrecognized_response'],
 ['redirect',0,'','unrecognized_response'],['network',null,'','request_failed'],['timeout',null,'','request_failed']];
 for(const [name,status,body,code] of cases){
  fixture={kind:name,status,body};requests=[];
  const context=await browser.newContext();
  await context.route('**/*',route=>new URL(route.request().url()).origin===origin?route.continue():route.abort());
  const page=await context.newPage();const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.fetchCalls=[];const originalFetch=window.fetch;window.fetch=(url,options)=>{window.fetchCalls.push({url,method:options.method,credentials:options.credentials,cache:options.cache,redirect:options.redirect});return originalFetch(url,options);};window.violations=[];addEventListener('securitypolicyviolation',e=>window.violations.push(e.violatedDirective));});
  const response=await page.goto(origin+'/access-ready');assert.equal(response.status(),200);
  const nonce=await page.locator('script').evaluate(e=>e.nonce);assert.match(response.headers()['content-security-policy'],new RegExp("script-src 'nonce-"+nonce+"'"));
  await page.waitForTimeout(150);assert.equal(requests.length,0);
  await page.locator('#check').click();
  await page.evaluate(()=>{for(let i=0;i<20;i++)document.querySelector('#check').click();});
  const expected=status===null?'HTTP unavailable · request_failed':`HTTP ${status} · ${code}`;
  await page.waitForFunction(expected=>document.querySelector('#result').textContent===expected,expected,{timeout:15000});
  await page.evaluate(()=>document.querySelector('#check').click());
  await page.waitForTimeout(100);if(name==='network')assert.ok(requests.length>=1,'network failure reaches local fixture; browser transport retries may occur');else assert.equal(requests.length,1);
  for(const request of requests)assert.deepEqual(request,{url:'/api/me',method:'GET',body:'',mode:'cors',dest:'empty',site:'same-origin'});
  assert.deepEqual(await page.evaluate(()=>window.fetchCalls),[{url:'/api/me',method:'GET',credentials:'same-origin',cache:'no-store',redirect:'manual'}]);assert.equal(await page.locator('#check').isDisabled(),true);assert.equal((await page.locator('body').innerText()).includes(sentinel),false);
  assert.deepEqual(await page.evaluate(()=>window.violations),[]);assert.deepEqual(errors,[]);
  if(name==='user')await page.screenshot({path:path.join(output,'success.png')});
  results.push({name,result:expected,requests:[...requests],cspViolations:0,applicationFetches:1});await context.close();
 }
 assert.equal(redirectHits,0);
 enabled=false;requests=[];const page=await browser.newPage();const response=await page.goto(origin+'/access-ready');assert.equal(response.status(),503);assert.equal(await page.locator('#check').isDisabled(),true);await page.evaluate(()=>document.querySelector('#check').click());await page.waitForTimeout(150);assert.equal(requests.length,0);assert.equal(await page.locator('#result').innerText(),'Relay unavailable');results.push({name:'missing-bindings',status:503,requests:0});
 for(const url of ['http://127.0.0.1/access-ready','https://graphs.holloman-ext.com/other','https://graphs.holloman-ext.com/access-ready?q=1'])assert.equal(onRequest({request:new Request(url),env}).status,404);
 assert.equal(onRequest({request:new Request('https://graphs.holloman-ext.com/access-ready',{method:'POST'}),env}).status,404);
 fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({browser:await browser.version(),results,redirectHits,guardChecks:4},null,2));console.log('Artifacts: '+output);console.log(`PASS: ${results.length} browser scenarios; 4 handler guard checks; redirect target hits ${redirectHits}`);
 }finally{await browser.close();server.closeAllConnections();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});

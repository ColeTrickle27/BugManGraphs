import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker, {searchAddress} from '../../tool/satellite_preview/worker.mjs';

const addressRequest = () => new Request('https://preview.example/api/preview/address-search?address=363+Carroll+Store+Rd%2C+Autryville%2C+NC');

test('Census search returns valid NC coordinates and filters other states', async () => {
  const response=await searchAddress(addressRequest(),async (url, options) => {
    const request=new URL(url);
    assert.equal(request.hostname,'geocoding.geo.census.gov');
    assert.equal(request.searchParams.get('address'),'363 Carroll Store Rd, Autryville, NC');
    assert.ok(options.signal);
    return Response.json({result:{addressMatches:[
      {matchedAddress:'363 CARROLL STORE RD, AUTRYVILLE, NC, 28318',coordinates:{x:-78.6196,y:35.0924},addressComponents:{state:'NC'}},
      {matchedAddress:'Elsewhere',coordinates:{x:-78,y:38},addressComponents:{state:'VA'}},
      {matchedAddress:'Invalid',coordinates:{x:0,y:0},addressComponents:{state:'NC'}}
    ]}});
  });
  assert.equal(response.status,200);
  assert.deepEqual((await response.json()).matches,[{address:'363 CARROLL STORE RD, AUTRYVILLE, NC, 28318',latitude:35.0924,longitude:-78.6196}]);
});
test('empty searches and unsupported methods never contact the provider',async () => {
  const fail=()=>{throw new Error('Unexpected fetch')};
  assert.equal((await searchAddress(new Request('https://preview.example/api/preview/address-search'),fail)).status,400);
  assert.equal((await searchAddress(new Request(addressRequest(),{method:'POST'}),fail)).status,405);
});
test('provider failures are readable errors',async()=>{
  for(const fetcher of [async()=>new Response('Unavailable',{status:503}),async()=>{throw new Error('Timeout')}]){
    const response=await searchAddress(addressRequest(),fetcher);
    assert.equal(response.status,503);
    assert.match((await response.json()).error,/temporarily unavailable/);
  }
});
test('non-API requests go only to deployed static assets',async()=>{
  let served=false;
  const response=await worker.fetch(new Request('https://preview.example/main.dart.js'),{ASSETS:{fetch:async()=>{served=true;return new Response('asset')}}});
  assert.equal(await response.text(),'asset');assert.ok(served);
});

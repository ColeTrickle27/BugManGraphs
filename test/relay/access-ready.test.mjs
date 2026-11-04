import {test} from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {onRequest, probeScript} from '../../functions/access-ready.js';

const origin = 'https://graphs.holloman-ext.com';
const sentinel = 'SYNTHETIC_BINDING_NEVER_RENDER';
const enabled = {
  GRAPH_DRAFTS_RELAY_ENABLED: 'true',
  GRAPH_OPS_ACCESS_CLIENT_ID: sentinel,
  GRAPH_OPS_ACCESS_CLIENT_SECRET: sentinel,
};
const response = (env = enabled, url = origin + '/access-ready', method = 'GET') =>
  onRequest({request: new Request(url, {method}), env});

test('probe compiles as a classic browser script', () => {
  assert.ok(new vm.Script(probeScript));
});

test('only canonical GET without query is served', () => {
  for (const [url, method] of [
    ['http://127.0.0.1/access-ready', 'GET'],
    ['https://preview.bugman-graphs.pages.dev/access-ready', 'GET'],
    [origin + '/other', 'GET'],
    [origin + '/access-ready?returnTo=synthetic', 'GET'],
    [origin + '/access-ready', 'POST'],
  ]) assert.equal(response(enabled, url, method).status, 404);
});

test('all three synthetic prerequisites are needed for the button', async () => {
  for (const env of [
    {},
    {...enabled, GRAPH_DRAFTS_RELAY_ENABLED: 'false'},
    {...enabled, GRAPH_OPS_ACCESS_CLIENT_ID: ''},
    {...enabled, GRAPH_OPS_ACCESS_CLIENT_SECRET: ''},
  ]) {
    const result = response(env);
    assert.equal(result.status, 503);
    const html = await result.text();
    assert.match(html, /id="check" disabled/);
    assert.match(html, /Relay unavailable/);
    assert.equal(html.includes(sentinel), false);
  }
});

test('ready HTML uses a fresh matching nonce and private security headers', async () => {
  const first = response();
  assert.equal(first.status, 200);
  assert.equal(first.headers.get('Content-Type'), 'text/html; charset=utf-8');
  assert.equal(first.headers.get('Cache-Control'), 'private, no-store');
  assert.equal(first.headers.get('X-Content-Type-Options'), 'nosniff');
  assert.equal(first.headers.get('Referrer-Policy'), 'no-referrer');
  const html = await first.text();
  const nonce = html.match(/<script nonce="([a-f0-9]{32})">/)[1];
  assert.equal(first.headers.get('Content-Security-Policy'), `default-src 'none'; script-src 'nonce-${nonce}'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`);
  assert.equal(html.includes(sentinel), false);
  assert.notEqual((await response().text()).match(/<script nonce="([a-f0-9]{32})">/)[1], nonce);
});

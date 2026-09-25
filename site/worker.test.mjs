import assert from 'node:assert/strict';
import { test } from 'node:test';
import worker from './worker.mjs';

const env = {
  ASSETS: {
    fetch: async (request) => {
      const path = new URL(request.url).pathname;
      if (path === '/updates/appcast.xml') {
        return new Response('<enclosure url="https://performancedaddy.significanthobbies.com/updates/performancedaddy-0.2.3-build3-universal.dmg"/>', { status: 200 });
      }
      return new Response(`asset:${path}`, { status: 200 });
    },
  },
};

test('serves /updates/* on performance.daddyrad.com', async () => {
  const feed = await worker.fetch(new Request('https://performance.daddyrad.com/updates/appcast.xml'), env);
  assert.equal(feed.status, 200);
  assert.match(await feed.text(), /<enclosure url=/);
  assert.equal(feed.headers.get('X-Content-Type-Options'), 'nosniff');
});

test('retired hostname redirects every path to performance.daddyrad.com', async () => {
  for (const path of ['/', '/updates/appcast.xml', '/updates/x.dmg?v=1']) {
    const response = await worker.fetch(new Request(`https://performancedaddy.significanthobbies.com${path}`), env);
    assert.equal(response.status, 308, path);
    assert.equal(response.headers.get('location'), `https://performance.daddyrad.com${path}`);
  }
});

test('serves /download as the newest feed DMG', async () => {
  const response = await worker.fetch(new Request('https://performance.daddyrad.com/download'), env);
  assert.equal(response.status, 200);
  assert.equal(await response.text(), 'asset:/updates/performancedaddy-0.2.3-build3-universal.dmg');
  assert.equal(response.headers.get('Content-Type'), 'application/x-apple-diskimage');
  assert.match(response.headers.get('Content-Disposition') ?? '', /performancedaddy-0\.2\.3-build3-universal\.dmg/);
  const head = await worker.fetch(new Request('https://performance.daddyrad.com/download', { method: 'HEAD' }), env);
  assert.equal(head.status, 200);
});

test('proxies non-updates paths to the Pages landing', async () => {
  const original = globalThis.fetch;
  let requested;
  globalThis.fetch = async (input) => { requested = input.url; return new Response('landing', { status: 200 }); };
  try {
    const response = await worker.fetch(new Request('https://performance.daddyrad.com/release/?a=1'), env);
    assert.equal(response.status, 200);
    assert.equal(requested, 'https://performancedaddy-landing.pages.dev/release/?a=1');
  } finally {
    globalThis.fetch = original;
  }
});

test('unknown hosts 404', async () => {
  const other = await worker.fetch(new Request('https://example.com/updates/appcast.xml'), env);
  assert.equal(other.status, 404);
});

test('rejects non-read methods', async () => {
  const response = await worker.fetch(new Request('https://performance.daddyrad.com/updates/appcast.xml', { method: 'POST' }), env);
  assert.equal(response.status, 405);
});

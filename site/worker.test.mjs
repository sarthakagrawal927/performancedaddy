import assert from 'node:assert/strict';
import { test } from 'node:test';
import worker from './worker.mjs';

const env = {
  ASSETS: {
    fetch: async (request) => new Response(`asset:${new URL(request.url).pathname}`, { status: 200 }),
  },
};

test('serves only /updates/* on the updates domain', async () => {
  const feed = await worker.fetch(new Request('https://performancedaddy.significanthobbies.com/updates/appcast.xml'), env);
  assert.equal(feed.status, 200);
  assert.equal(await feed.text(), 'asset:/updates/appcast.xml');
  assert.equal(feed.headers.get('X-Content-Type-Options'), 'nosniff');

  for (const path of ['/', '/index.html', '/updates']) {
    const response = await worker.fetch(new Request(`https://performancedaddy.significanthobbies.com${path}`), env);
    assert.equal(response.status, 404, path);
  }
  const other = await worker.fetch(new Request('https://example.com/updates/appcast.xml'), env);
  assert.equal(other.status, 404);
});

test('rejects non-read methods', async () => {
  const response = await worker.fetch(new Request('https://performancedaddy.significanthobbies.com/updates/appcast.xml', { method: 'POST' }), env);
  assert.equal(response.status, 405);
});

// Updates-only worker: owns /updates/* alongside the ios-landings Pages site,
// which keeps every other path on performancedaddy.significanthobbies.com.
/** @param {Response} response */
function secure(response) {
  const result = new Response(response.body, response);
  result.headers.set('X-Content-Type-Options', 'nosniff');
  result.headers.set('Referrer-Policy', 'no-referrer');
  result.headers.set('Content-Security-Policy', "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  return result;
}
export default {
  /** @param {Request} request @param {Env} env */
  async fetch(request, env) {
    if (!['GET', 'HEAD'].includes(request.method)) return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
    const url = new URL(request.url);
    if (url.hostname !== 'performancedaddy.significanthobbies.com' || !url.pathname.startsWith('/updates/')) {
      return new Response('Not found', { status: 404 });
    }
    const response = await env.ASSETS.fetch(request);
    return secure(response);
  },
};

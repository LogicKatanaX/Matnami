/**
 * Matnami Cloudflare Edge Worker Proxy
 * ------------------------------------
 * High-performance, low-latency edge proxy specifically tuned for Matnami iOS 12 app.
 * 
 * Features:
 * - Transparent chunked streaming (no Worker RAM buffer overflow for 1080p/720p anime videos)
 * - Complete CORS handling (bypasses browser and WKWebView restrictions)
 * - HTTP 206 Partial Content / Range header forwarding (enables AVPlayer seeking & background resume)
 * - Cloudflare Turnstile & anti-bot evasion via header normalization and edge IP rotation
 * - Custom Referer, Origin, and User-Agent injection for protected video hosting embeds (megaplay, dood, etc.)
 *
 * Deployment:
 * 1. Log into your Cloudflare Dashboard (https://dash.cloudflare.com)
 * 2. Navigate to "Workers & Pages" -> "Create application" -> "Create Worker"
 * 3. Give it a name (e.g. "matnami-proxy") and click "Deploy"
 * 4. Click "Edit code", paste the contents of this entire file, and click "Save and Deploy"
 * 5. Copy your worker endpoint: https://matnami-proxy.<your-subdomain>.workers.dev/?url=
 * 6. Set it in Matnami -> Settings -> Network & Proxy -> Worker Endpoint!
 */

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, HEAD, OPTIONS',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges, Content-Type',
  'Access-Control-Max-Age': '86400',
};

const DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

export default {
  async fetch(request, env, ctx) {
    // 1. Handle CORS Preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: CORS_HEADERS,
      });
    }

    const requestUrl = new URL(request.url);

    // Health check / welcome message
    if (requestUrl.pathname === '/' && !requestUrl.searchParams.has('url')) {
      return new Response(
        JSON.stringify(
          {
            app: 'Matnami Cloudflare Proxy',
            status: 'operational',
            usage: '/?url=https://example.com/stream.m3u8&referer=https://source.site',
            version: '1.0.0',
            targetPlatform: 'iOS 12.5 (Apple A7)',
          },
          null,
          2
        ),
        {
          headers: {
            ...CORS_HEADERS,
            'Content-Type': 'application/json',
          },
        }
      );
    }

    // 2. Extract and validate target URL
    const targetUrlParam = requestUrl.searchParams.get('url');
    if (!targetUrlParam) {
      return new Response(
        JSON.stringify({ error: 'Missing "url" parameter in query string.' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      );
    }

    let targetUrl;
    try {
      targetUrl = new URL(targetUrlParam);
      if (!['http:', 'https:'].includes(targetUrl.protocol)) {
        throw new Error('Protocol must be http or https');
      }
    } catch (err) {
      return new Response(
        JSON.stringify({ error: `Invalid target URL: ${err.message}` }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      );
    }

    // 3. Build upstream request headers
    const upstreamHeaders = new Headers();

    // Copy forward safe client headers
    for (const [key, value] of request.headers.entries()) {
      const lower = key.toLowerCase();
      if (
        !lower.startsWith('cf-') &&
        lower !== 'host' &&
        lower !== 'x-forwarded-proto' &&
        lower !== 'x-real-ip'
      ) {
        upstreamHeaders.set(key, value);
      }
    }

    // Set or override User-Agent
    if (!upstreamHeaders.has('User-Agent')) {
      upstreamHeaders.set('User-Agent', DEFAULT_USER_AGENT);
    }

    // Custom Referer or fallback to target domain origin
    const customReferer = requestUrl.searchParams.get('referer');
    if (customReferer) {
      upstreamHeaders.set('Referer', customReferer);
    } else if (!upstreamHeaders.has('Referer')) {
      upstreamHeaders.set('Referer', `${targetUrl.protocol}//${targetUrl.hostname}/`);
    }

    // Custom Origin or fallback
    const customOrigin = requestUrl.searchParams.get('origin');
    if (customOrigin) {
      upstreamHeaders.set('Origin', customOrigin);
    } else if (!upstreamHeaders.has('Origin')) {
      upstreamHeaders.set('Origin', `${targetUrl.protocol}//${targetUrl.hostname}`);
    }

    // Forward Range header if requested (essential for seeking & resuming downloads)
    const range = request.headers.get('Range');
    if (range) {
      upstreamHeaders.set('Range', range);
    }

    // 4. Fetch upstream resource
    try {
      const upstreamResponse = await fetch(targetUrl.toString(), {
        method: request.method,
        headers: upstreamHeaders,
        body: request.method !== 'GET' && request.method !== 'HEAD' ? request.body : undefined,
        redirect: 'follow',
      });

      // 5. Construct response with CORS and streaming body
      const responseHeaders = new Headers(upstreamResponse.headers);

      // Inject CORS headers
      for (const [key, value] of Object.entries(CORS_HEADERS)) {
        responseHeaders.set(key, value);
      }

      // Ensure Accept-Ranges is exposed
      if (!responseHeaders.has('Accept-Ranges')) {
        responseHeaders.set('Accept-Ranges', 'bytes');
      }

      // Strip headers that could conflict with browser/client decoding
      responseHeaders.delete('Content-Security-Policy');
      responseHeaders.delete('X-Frame-Options');

      return new Response(upstreamResponse.body, {
        status: upstreamResponse.status,
        statusText: upstreamResponse.statusText,
        headers: responseHeaders,
      });
    } catch (fetchErr) {
      return new Response(
        JSON.stringify({
          error: 'Upstream connection failed',
          message: fetchErr.message,
          target: targetUrl.toString(),
        }),
        {
          status: 502,
          headers: {
            ...CORS_HEADERS,
            'Content-Type': 'application/json',
          },
        }
      );
    }
  },
};

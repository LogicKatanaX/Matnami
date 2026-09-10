/**
 * Matnami Cloudflare Worker Reverse Proxy
 * ========================================
 * High-performance edge proxy for anime streaming, manga scraping, and downloads.
 * 
 * Features:
 *   • Full CORS bypass for any origin
 *   • HTTP Range request forwarding (essential for AVPlayer video streaming & seeking)
 *   • Streamed chunked transfer for large video files (no memory limits)
 *   • Bypasses ISP-level DNS sinkholing & SNI blocking (e.g. India DoT blocks)
 * 
 * Usage:
 *   https://<your-worker-name>.workers.dev/?url=https://example.com/video.mp4
 */

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, HEAD, POST, OPTIONS',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges, Content-Type',
};

async function handleRequest(request) {
  // Handle CORS preflight
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: CORS_HEADERS
    });
  }

  const urlObj = new URL(request.url);
  const targetUrl = urlObj.searchParams.get('url');

  if (!targetUrl) {
    return new Response(JSON.stringify({
      status: 'online',
      service: 'Matnami Cloudflare Edge Proxy',
      version: '2.0',
      usage: `${urlObj.origin}/?url=https://example.com/stream.mp4`
    }, null, 2), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        ...CORS_HEADERS
      }
    });
  }

  try {
    const dest = new URL(targetUrl);

    // Forward necessary headers
    const forwardHeaders = new Headers();
    forwardHeaders.set('User-Agent', request.headers.get('User-Agent') || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    forwardHeaders.set('Accept', request.headers.get('Accept') || '*/*');
    forwardHeaders.set('Accept-Language', 'en-US,en;q=0.9');

    // Forward Range header for AVPlayer seeking & streaming
    const range = request.headers.get('Range');
    if (range) {
      forwardHeaders.set('Range', range);
    }

    // Set Referer to destination origin to prevent 403 hotlink blocks
    const referer = request.headers.get('Referer');
    if (referer && !referer.includes(urlObj.hostname)) {
      forwardHeaders.set('Referer', referer);
    } else {
      forwardHeaders.set('Referer', dest.origin + '/');
    }

    const init = {
      method: request.method,
      headers: forwardHeaders,
      redirect: 'follow'
    };

    if (request.method === 'POST' && request.body) {
      init.body = request.body;
    }

    const response = await fetch(targetUrl, init);

    // Build response headers preserving Content-Range, Content-Length, Content-Type
    const responseHeaders = new Headers(response.headers);
    for (const [key, value] of Object.entries(CORS_HEADERS)) {
      responseHeaders.set(key, value);
    }

    // Always advertise Accept-Ranges for media playback
    if (!responseHeaders.has('Accept-Ranges')) {
      responseHeaders.set('Accept-Ranges', 'bytes');
    }

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: responseHeaders
    });

  } catch (err) {
    return new Response(JSON.stringify({
      error: 'Proxy Fetch Failed',
      message: err.message,
      target: targetUrl
    }), {
      status: 502,
      headers: {
        'Content-Type': 'application/json',
        ...CORS_HEADERS
      }
    });
  }
}

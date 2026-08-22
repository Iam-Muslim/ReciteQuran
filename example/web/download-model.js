export async function onRequest(context) {
    const { request } = context;
    
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
        return new Response(null, {
            status: 204,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
                'Access-Control-Allow-Headers': '*',
                'Access-Control-Max-Age': '86400',
            }
        });
    }

    const urlObj = new URL(request.url);
    const modelParam = urlObj.searchParams.get('model') || 'zipformer_p_arabic_v3.int8.onnx';
    
    const directUrl = `https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/${modelParam}`;
    
    const requestHeaders = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    };

    // Forward Range header if requested by client
    const rangeHeader = request.headers.get('Range');
    if (rangeHeader) {
        requestHeaders['Range'] = rangeHeader;
    }

    // Fetch directly from github releases.
    const fetchResponse = await fetch(directUrl, {
        method: request.method,
        headers: requestHeaders
    });

    const headers = new Headers();
    headers.set('Access-Control-Allow-Origin', '*');
    headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    headers.set('Access-Control-Allow-Headers', '*');
    headers.set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');
    headers.set('Accept-Ranges', 'bytes');
    headers.set('Content-Type', 'application/octet-stream');
    
    const contentLength = fetchResponse.headers.get('content-length');
    if (contentLength) {
        headers.set('Content-Length', contentLength);
    }

    const contentRange = fetchResponse.headers.get('content-range');
    if (contentRange) {
        headers.set('Content-Range', contentRange);
    }
    
    // Enforce no-caching on Cloudflare
    headers.set('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');

    return new Response(request.method === 'HEAD' ? null : fetchResponse.body, {
        status: fetchResponse.status,
        headers: headers
    });
}

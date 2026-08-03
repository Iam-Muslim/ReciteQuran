export async function onRequest(context) {
    const url = 'https://github.com/Iam-Muslim/ReciteQuran/releases/download/v1.1.0/zipformer_p_arabic_v2.int8.onnx';
    const githubResponse = await fetch(url, { headers: { 'User-Agent': 'Cloudflare-Worker' } });
    const response = new Response(githubResponse.body, githubResponse);
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    return response;
}

export async function onRequest(context) {
    const url = 'https://github.com/Iam-Muslim/ReciteQuran/releases/download/v9.0.0/quran_phoneme_zipformer.int8.onnx';
    const githubResponse = await fetch(url, { headers: { 'User-Agent': 'Cloudflare-Worker' } });
    const response = new Response(githubResponse.body, githubResponse);
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    return response;
}

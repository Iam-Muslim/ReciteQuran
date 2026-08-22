// Service Worker for Recite Quran (اتلو القران)
// Provides complete offline caching, auto-updating, and Cross-Origin Isolation (COOP/COEP) for WebAssembly.

const CACHE_NAME = 'recite-quran-pwa-v7';

const STATIC_PRECACHE = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'apple-touch-icon.png',
  'apple-touch-icon-precomposed.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'pwa_install.js',
  'audio_worklet.js',
  'sherpa-onnx-asr.js?v=6',
  'sherpa_official_app.js?v=6',
  'sherpa-onnx-wasm-main-asr.js?v=6',
  'sherpa-onnx-wasm-main-asr.wasm',
  'flutter_bootstrap.js',
  'main.dart.js',
  'assets/FontManifest.json',
  'assets/AssetManifest.json',
  'assets/AssetManifest.bin.json',
  'assets/fonts/HafsSmart_08.ttf',
  'assets/model/tokens.txt',
  'assets/model/ordered_quran_phonemes.json',
  'assets/model/ph_index.npy',
  'assets/model/ref_norm_ph.txt'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[SW] Precaching all essential assets for complete offline readiness...');
      return Promise.allSettled(
        STATIC_PRECACHE.map((url) =>
          cache.add(url).catch((err) => {
            console.warn('[SW] Precache item optional/skipped:', url, err);
          })
        )
      );
    })
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            console.log('[SW] Purging outdated cache:', key);
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

function addCoopCoepHeaders(response) {
  if (!response || response.status === 0 || response.type === 'opaque') {
    return response;
  }
  if ([101, 204, 205, 304].includes(response.status)) {
    return response;
  }
  const newHeaders = new Headers(response.headers);
  newHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
  newHeaders.set('Cross-Origin-Embedder-Policy', 'credentialless');
  newHeaders.set('Cross-Origin-Resource-Policy', 'cross-origin');

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: newHeaders
  });
}

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') {
    return;
  }

  const url = new URL(event.request.url);

  // 1. Model download endpoint is stored in IndexedDB, do not cache inside ServiceWorker
  if (url.pathname.includes('/download-model')) {
    return;
  }

  // 2. Navigation requests (Page loading): Network First, fallback to cached index.html
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            const cloned = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, cloned));
          }
          return addCoopCoepHeaders(networkResponse);
        })
        .catch(async () => {
          console.log('[SW] Offline mode detected. Serving cached index.html');
          const cached = await caches.match(event.request, { ignoreSearch: true });
          if (cached) return addCoopCoepHeaders(cached);
          const fallback = (await caches.match('index.html')) || (await caches.match('./'));
          return fallback ? addCoopCoepHeaders(fallback) : Response.error();
        })
    );
    return;
  }

  // 3. Static assets & CanvasKit: Cache First, fallback to Network (and cache dynamically)
  event.respondWith(
    caches.match(event.request, { ignoreSearch: true }).then((cachedResponse) => {
      if (cachedResponse) {
        return cachedResponse;
      }

      return fetch(event.request).then((networkResponse) => {
        if (networkResponse && networkResponse.status === 200) {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseToCache);
          });
        }
        return networkResponse;
      }).catch(async (fetchErr) => {
        console.warn('[SW] Offline fetch fallback for:', event.request.url);
        const fallback = await caches.match(url.pathname, { ignoreSearch: true });
        if (fallback) return fallback;
        return Response.error();
      });
    })
  );
});


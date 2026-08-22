// PWA Installation & Offline Service Worker Manager for Recite Quran (اتلو القران)
(function() {
  let deferredInstallPrompt = null;

  function checkIsStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches || 
           window.navigator.standalone === true ||
           window.location.search.includes('source=pwa');
  }

  // 1. Register Service Worker for offline functionality, background updates & COOP/COEP support
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('sw.js').then((reg) => {
        console.log('[PWA] ServiceWorker registered with scope:', reg.scope);
        if (navigator.onLine) {
          reg.update().catch(console.warn);
        }
      }).catch((err) => {
        console.warn('[PWA] ServiceWorker registration failed:', err);
      });
    });
  }

  // If currently running in standalone/installed mode, do not show prompts
  if (checkIsStandalone()) {
    console.log('[PWA] Running in standalone PWA mode. Prompts suppressed.');
    return;
  }

  // Listen for successful installation from browser
  window.addEventListener('appinstalled', () => {
    console.log('[PWA] Application successfully installed to home screen.');
    deferredInstallPrompt = null;
    const banner = document.getElementById('pwa-install-banner');
    const iosBanner = document.getElementById('pwa-ios-banner');
    if (banner) banner.style.display = 'none';
    if (iosBanner) iosBanner.style.display = 'none';
  });

  // 2. Android / Windows / Chromium Automatic Install Prompt
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredInstallPrompt = e;
    console.log('[PWA] beforeinstallprompt captured.');
    setTimeout(showInstallBanner, 1500);
  });

  function showInstallBanner() {
    if (checkIsStandalone()) return;
    if (sessionStorage.getItem('pwa_banner_dismissed') === 'true') return;

    const banner = document.getElementById('pwa-install-banner');
    const installBtn = document.getElementById('pwa-install-btn');
    const closeBtn = document.getElementById('pwa-close-btn');

    if (!banner || !installBtn) return;
    banner.style.display = 'block';

    installBtn.onclick = async () => {
      if (deferredInstallPrompt) {
        deferredInstallPrompt.prompt();
        const choiceResult = await deferredInstallPrompt.userChoice;
        console.log(`[PWA] Install prompt outcome: ${choiceResult.outcome}`);
        deferredInstallPrompt = null;
        banner.style.display = 'none';
      }
    };

    if (closeBtn) {
      closeBtn.onclick = () => {
        banner.style.display = 'none';
        sessionStorage.setItem('pwa_banner_dismissed', 'true');
      };
    }
  }

  // 3. iOS Safari Guided Install Prompt
  const isIos = /iphone|ipad|ipod/.test(navigator.userAgent.toLowerCase()) || 
                (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  const isInAppBrowser = /(FBAN|FBAV|Instagram|Twitter|Line|WhatsApp|Snapchat|Telegram)/i.test(navigator.userAgent);

  if (isIos && !checkIsStandalone() && !isInAppBrowser) {
    const isSafari = /safari/.test(navigator.userAgent.toLowerCase()) && 
                     !/crios|fxios|opios|mercury|edgios/i.test(navigator.userAgent);
    if (isSafari) {
      setTimeout(() => {
        if (checkIsStandalone()) return;
        if (sessionStorage.getItem('pwa_banner_dismissed') === 'true') return;

        const iosBanner = document.getElementById('pwa-ios-banner');
        const iosCloseBtn = document.getElementById('pwa-ios-close-btn');
        if (iosBanner) {
          iosBanner.style.display = 'block';
          if (iosCloseBtn) {
            iosCloseBtn.onclick = () => {
              iosBanner.style.display = 'none';
              sessionStorage.setItem('pwa_banner_dismissed', 'true');
            };
          }
        }
      }, 2500);
    }
  }
})();


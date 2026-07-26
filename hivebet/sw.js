/* HiveBet service worker — enables install + basic offline shell. */
const CACHE = 'hivebet-v1';
const ASSETS = [
  'assets/css/style.css',
  'assets/js/main.js',
  'assets/icon.svg',
  'manifest.webmanifest',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;                       // never cache POSTs (bets, auth)
  const url = new URL(req.url);
  // Cache-first for static assets; network-first for everything else (live data).
  if (/\.(css|js|svg|png|webmanifest)$/.test(url.pathname)) {
    e.respondWith(caches.match(req).then((hit) => hit || fetch(req)));
  } else {
    e.respondWith(fetch(req).catch(() => caches.match(req)));
  }
});

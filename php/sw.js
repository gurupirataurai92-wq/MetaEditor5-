/* SIMS AI (XAMPP edition) service worker — makes the app installable and
   keeps the shell available if the connection drops. Dynamic pages are always
   fetched fresh (network-first); static assets are cache-first. */
const CACHE = 'sims-ai-php-v1';
const ASSETS = ['assets/style.css', 'assets/app.js'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // Static assets: cache-first.
  if (/\.(css|js|svg|png|webmanifest)$/.test(url.pathname)) {
    e.respondWith(
      caches.match(req).then((hit) => hit || fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy));
        return res;
      }))
    );
    return;
  }

  // Dynamic PHP pages: network-first, fall back to cache if offline.
  e.respondWith(fetch(req).catch(() => caches.match(req)));
});

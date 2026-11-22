// Offline cache for the home-screen app. The version changes with every build, so updates replace the old copy.
const CACHE = 'patrol-test-ca27a7215445'; // TEST build: own cache, scope /FINEST-HQ/test/
const FILES = ['./', './index.html', './config.js', './manifest.webmanifest', './icons/favicon-16.png', './icons/favicon-32.png', './icons/apple-touch-icon.png', './icons/icon-192.png', './icons/icon-512.png', './icons/icon-maskable-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE && k.indexOf('patrol-test-') === 0).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin) return; // Supabase calls go straight to the network
  // app files: network first (fresh when online), cache when offline
  e.respondWith(fetch(e.request).then(r => { const c = r.clone(); if (r.ok) caches.open(CACHE).then(x => x.put(e.request, c)); return r; }).catch(() => caches.open(CACHE).then(x => x.match(e.request, { ignoreSearch: true }).then(r => r || x.match('./index.html')))));
});
self.addEventListener('push', e => {
  let data = {};
  try { data = e.data ? e.data.json() : {}; } catch (err) { data = { body: e.data && e.data.text && e.data.text() }; }
  const title = data.title || 'New suggestion';
  const opts = { body: data.body || 'A tester sent a suggestion.', data: { url: data.url || './?inbox=1' }, icon: './icons/icon-192.png', badge: './icons/icon-192.png' };
  e.waitUntil(self.registration.showNotification(title, opts));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || './?inbox=1';
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (let i = 0; i < list.length; i++) { const c = list[i]; if (c && c.focus) { c.postMessage({ type: 'open-inbox' }); return c.focus(); } }
    if (self.clients.openWindow) return self.clients.openWindow(url);
  }));
});

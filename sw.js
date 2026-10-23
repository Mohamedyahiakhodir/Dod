const CACHE = 'voice-studio-v1';
const ASSETS = [
  './', 'index.html', 'manifest.webmanifest', 'css/app.css', 'icons/icon.svg', 'icons/icon-192.png', 'icons/icon-512.png',
  'js/app.js', 'js/util.js', 'js/icons.js', 'js/ui.js', 'js/audio.js', 'js/fx.js', 'js/ops.js', 'js/dsp.js', 'js/worker.js',
  'js/db.js', 'js/project.js', 'js/recorder.js', 'js/record-view.js', 'js/library-view.js', 'js/editor.js', 'js/player.js',
  'js/tools.js', 'js/export.js', 'vendor/lame.min.js',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    fetch(e.request).then((r) => {
      const copy = r.clone();
      if (r.ok) caches.open(CACHE).then((c) => c.put(e.request, copy));
      return r;
    }).catch(() => caches.match(e.request).then((r) => r || caches.match('index.html'))),
  );
});

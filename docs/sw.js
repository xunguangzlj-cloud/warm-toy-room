
const NAME = "toyroom-shell-device-pack-v1";
const FILES = ["index.html","index.js","index.audio.worklet.js","index.audio.position.worklet.js","payload.js","profiles.js","boot.js","asset-loader.js","gzip-worker.js","touch.js","shell.css","touch.css","vendor/fflate-0.8.2.js","manifest.webmanifest","icon-180.png","icon-192.png","icon-512.png"];
self.addEventListener("install", event => event.waitUntil(caches.open(NAME).then(c => c.addAll(FILES)).then(() => self.skipWaiting())));
self.addEventListener("activate", event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith("toyroom-shell-") && k !== NAME).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", event => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.origin !== location.origin || url.pathname.includes("/payload/")) return;
  const relative = url.pathname.slice(new URL(self.registration.scope).pathname.length);
  if (event.request.mode !== "navigate" && !FILES.includes(relative)) return;
  // Online visits always get the published version. Offline can reuse this shell.
  event.respondWith(fetch(event.request).catch(() => caches.open(NAME).then(c => c.match(event.request.mode === "navigate" ? "index.html" : relative)).then(r => r || Response.error())));
});

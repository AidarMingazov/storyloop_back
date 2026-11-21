// Minimal service worker: makes Storyloop installable. Pages always come from the network
// (episodes, words and progress must be fresh); offline reading is out of MVP scope.
self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))
self.addEventListener("fetch", () => {})

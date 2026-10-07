const LEGACY_FLUTTER_CACHE_NAMES = new Set([
  'flutter-app-cache',
  'flutter-temp-cache',
  'flutter-app-manifest',
]);

const EXPRESS_MAP_TILE_CACHE = 'express-map-tiles-v1';
const EXPRESS_MAP_TILE_CACHE_LIMIT = 420;
// Mapbox raster/static tile responses advertise a 12h device TTL.
// Never extend the cached lifetime beyond that window.
const EXPRESS_MAP_TILE_MAX_AGE_MS = 12 * 60 * 60 * 1000;

function isExpressMapTile(request) {
  if (!request || request.method !== 'GET') return false;

  try {
    const url = new URL(request.url);
    if (
      url.hostname === 'api.mapbox.com' &&
      url.pathname.includes('/styles/v1/') &&
      url.pathname.includes('/tiles/')
    ) {
      return true;
    }
    return url.hostname === 'tile.openstreetmap.org';
  } catch (_) {
    return false;
  }
}

async function trimMapTileCache(cache) {
  try {
    const keys = await cache.keys();
    const overflow = keys.length - EXPRESS_MAP_TILE_CACHE_LIMIT;
    if (overflow <= 0) return;
    await Promise.all(keys.slice(0, overflow).map((key) => cache.delete(key)));
  } catch (_) {}
}

function isFreshCachedMapTile(response) {
  if (!response) return false;
  try {
    const rawDate = response.headers.get('date');
    if (!rawDate) return false;
    const servedAt = Date.parse(rawDate);
    return Number.isFinite(servedAt) &&
      Date.now() - servedAt <= EXPRESS_MAP_TILE_MAX_AGE_MS;
  } catch (_) {
    return false;
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) =>
            LEGACY_FLUTTER_CACHE_NAMES.has(key) ||
            key.startsWith('flutter-')
          )
          .map((key) => caches.delete(key)),
      );
    } catch (_) {}

    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (!isExpressMapTile(request)) return;

  event.respondWith((async () => {
    try {
      const cache = await caches.open(EXPRESS_MAP_TILE_CACHE);
      const cached = await cache.match(request);
      if (cached && isFreshCachedMapTile(cached)) return cached;
      if (cached) {
        try { await cache.delete(request); } catch (_) {}
      }

      const response = await fetch(request);
      if (response && (response.ok || response.type === 'opaque')) {
        try {
          await cache.put(request, response.clone());
          await trimMapTileCache(cache);
        } catch (_) {}
      }
      return response;
    } catch (_) {
      const cache = await caches.open(EXPRESS_MAP_TILE_CACHE);
      const cached = await cache.match(request);
      if (cached && isFreshCachedMapTile(cached)) return cached;
      return new Response('', { status: 503, statusText: 'Offline' });
    }
  })());
});

self.addEventListener('message', (event) => {
  const data = event.data;
  if (
    data === 'SKIP_WAITING' ||
    (data && data.type === 'SKIP_WAITING')
  ) {
    self.skipWaiting();
  }
});

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = {
      title: 'Express',
      body: event.data ? event.data.text() : '',
      type: 'general',
      url: '/Expressdelivery/',
      urgent: false,
    };
  }

  const urgent = data.urgent === true;
  const title = data.title || 'Express';
  const body = data.body || 'Tienes una nueva notificación.';
  const notificationKey =
    data.notification_id || data.type || 'general';

  const options = {
    body,
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: 'express-' + notificationKey,
    renotify: false,
    silent: false,
    requireInteraction: urgent,
    vibrate: urgent
      ? [350, 120, 350, 120, 350, 120, 700]
      : [220, 100, 220],
    timestamp: Date.now(),
    data: {
      url: data.url || '/Expressdelivery/',
      type: data.type || 'general',
      notificationId: data.notification_id || null,
    },
  };

  event.waitUntil((async () => {
    // Si Express está abierto, avisamos a la ventana en el MISMO momento en
    // que llega la push. Esto acelera el refresco visual sin exigir que el
    // usuario toque la notificación.
    try {
      const windowClients = await clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      for (const client of windowClients) {
        try {
          client.postMessage({
            type: 'EXPRESS_PUSH_RECEIVED',
            notificationType: data.type || 'general',
            notificationId: data.notification_id || null,
          });
        } catch (_) {}
      }
    } catch (_) {}

    await self.registration.showNotification(title, options);
  })());
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const targetUrl =
    event.notification.data?.url || '/Expressdelivery/';

  event.waitUntil((async () => {
    const windowClients = await clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });

    for (const client of windowClients) {
      try {
        const clientUrl = new URL(client.url);
        if (clientUrl.origin === self.location.origin) {
          // La push es solo un aviso. Si Express ya está abierto, enfocarlo
          // jamás debe navegar/recargar la app ni reiniciar contadores.
          try {
            client.postMessage({
              type: 'EXPRESS_PUSH_CLICK',
              notificationType: event.notification.data?.type || 'general',
              notificationId:
                event.notification.data?.notificationId || null,
            });
          } catch (_) {}
          return client.focus();
        }
      } catch (_) {}
    }

    // Solo abrimos una ventana nueva cuando la aplicación realmente estaba cerrada.
    if (clients.openWindow) {
      return clients.openWindow(targetUrl);
    }
  })());
});

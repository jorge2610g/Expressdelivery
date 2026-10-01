const LEGACY_FLUTTER_CACHE_NAMES = new Set([
  'flutter-app-cache',
  'flutter-temp-cache',
  'flutter-app-manifest',
]);

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

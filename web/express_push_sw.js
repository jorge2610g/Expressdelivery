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

  const options = {
    body,
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: 'express-' + (data.type || 'general'),
    renotify: true,
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

  event.waitUntil(
    self.registration.showNotification(title, options),
  );
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
          if ('navigate' in client) {
            await client.navigate(targetUrl);
          }
          return client.focus();
        }
      } catch (_) {}
    }

    if (clients.openWindow) {
      return clients.openWindow(targetUrl);
    }
  })());
});

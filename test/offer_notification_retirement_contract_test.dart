import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato de avisos de nueva solicitud y de la burbuja:
/// - El aviso del sistema se retira solo de este paquete, en el canal de
///   urgencias y con el título de oferta.
/// - Se retira cuando la tarjeta queda confirmada, cuando la oferta desaparece
///   (aceptada, descartada o vencida) y al cerrar la tarjeta.
/// - Si el overlay no se confirma, el aviso de respaldo se conserva.
/// - La burbuja usa el logo oficial, no el icono predeterminado de Flutter.
void main() {
  final plugin = File(
    'android_overlay/kotlin/com/express/usuario1/FloatingOfferPlugin.kt',
  ).readAsStringSync();
  final bubble = File(
    'android_overlay/kotlin/com/express/usuario1/DriverBubbleService.kt',
  ).readAsStringSync();
  final dart = File('lib/driver_floating_offers.dart').readAsStringSync();

  test('native retirement is scoped to this package, urgent channel and offer title', () {
    expect(plugin, contains('"cancelOfferNotifications"'));
    expect(plugin, contains('RIDE_OFFER_CHANNEL = "express_urgent"'));
    expect(plugin, contains('RIDE_OFFER_TITLE = "Nueva solicitud disponible"'));
    expect(plugin, contains('if (active.packageName != ctx.packageName) continue'));
    expect(plugin, contains('if (notification.channelId != RIDE_OFFER_CHANNEL) continue'));
    expect(plugin, contains('if (title != RIDE_OFFER_TITLE) continue'));
    expect(plugin, contains('manager.cancel(active.tag, active.id)'));
  });

  test('bridge exposes retirement and controller retires on confirm, offer end and close', () {
    expect(dart, contains("invokeMethod<int>('cancelOfferNotifications')"));
    expect(dart, contains('_offerNotificationPending = true;'));
    // Expired, accepted or withdrawn offer: retire once.
    expect(dart, contains('} else if (_offerNotificationPending) {'));
    // Card confirmed by Android: retire the duplicate notification.
    expect(dart, contains('await bridge.retireOfferNotifications();\n        onShown?.call'));
    // close(): accept, reject, resume, offline.
    final closeBody = dart.substring(dart.indexOf('Future<void> close() async {'));
    expect(closeBody, contains('await bridge.retireOfferNotifications();'));
  });

  test('notification is kept when Android does not confirm the overlay', () {
    // The card-confirmed retirement lives only inside the `if (shown)` block,
    // so a failed native show leaves the fallback notification in place.
    final shownBranch = dart.indexOf('if (shown) {\n        // La tarjeta sustituye');
    expect(shownBranch, greaterThan(-1));
    final block = dart.substring(
      shownBranch,
      dart.indexOf('onShown?.call', shownBranch) + 1,
    );
    expect(block, contains('await bridge.retireOfferNotifications();'));
  });

  test('bubble uses the official Express logo, not the Flutter launcher icon', () {
    expect(bubble, contains('R.drawable.ic_express_notification_large'));
    expect(bubble, isNot(contains('R.mipmap.ic_launcher')));
  });
}

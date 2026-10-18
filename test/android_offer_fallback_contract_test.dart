import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato: si la barra no puede aparecer, la oferta debe llegar como aviso de
/// Android. Un servicio en primer plano (ubicación del conductor en línea) no cuenta
/// como app abierta, y un mismo offer_id no duplica ni silencia el aviso.
void main() {
  late String receiver;
  late String overlay;

  setUpAll(() {
    receiver = File('android_overlay/kotlin/com/express/usuario1/ExpressMessagingService.kt')
        .readAsStringSync();
    overlay = File('android_overlay/kotlin/com/express/usuario1/FloatingOfferService.kt')
        .readAsStringSync();
  });

  test('a foreground-service process is not treated as the app being open', () {
    // IMPORTANCE_FOREGROUND_SERVICE (125) <= IMPORTANCE_VISIBLE (200) era el fallo:
    // con la ubicación en línea la oferta se descartaba sin aviso.
    expect(receiver, isNot(contains('info.importance <= ')));
    expect(
      receiver,
      contains('info.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND'),
    );
    expect(
      receiver,
      contains('info.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE'),
    );
  });

  test('fallback notification is sent whenever the bar cannot be drawn', () {
    expect(receiver, contains('if (data["presentation"] == "overlay" && canDraw) {'));
    expect(receiver, contains('postFallbackNotification(context, offerId, data["title"], data["body"])'));
    // El aviso de respaldo también se usa cuando Android rechaza el arranque de la barra.
    expect(receiver, contains('if (started) return'));
    expect(overlay, contains('fallbackOrRefuse(intent, id)'));
  });

  test('a repeated offer replaces its notification instead of duplicating or silencing it', () {
    // Sin dedupe en memoria: un reintento tras un fallo no puede silenciar la oferta.
    expect(receiver, isNot(contains('lastReceivedOfferId')));
    expect(receiver, contains('manager.notify(OFFER_TAG_PREFIX + offerId, 0, notification)'));
    expect(receiver, contains('.setOnlyAlertOnce(true)'));
    // Una oferta ya dibujada no se vuelve a crear en la barra.
    expect(overlay, contains('if (incoming != null && card != null && drawnOfferId == incoming) return'));
  });

  test('blocked notifications are detected and documented, never reported as guaranteed', () {
    expect(receiver, contains('NotificationManagerCompat.from(context).areNotificationsEnabled()'));
    expect(receiver, contains('NotificationManager.IMPORTANCE_NONE'));
    expect(receiver, contains('avisos de Express desactivados'));
    expect(receiver, contains('no se declara respaldo garantizado'));
  });

  test('expired offers are not announced', () {
    expect(receiver, contains('if (expiresAt > 0L && expiresAt <= System.currentTimeMillis())'));
  });

  test('tapping the fallback opens the app without CLEAR_TOP on the singleInstance activity', () {
    expect(receiver, contains('Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP'));
    expect(receiver, isNot(contains('FLAG_ACTIVITY_CLEAR_TOP')));
  });

  test('the local QA harness is never part of the committed overlay sources', () {
    final dir = Directory('android_overlay/kotlin/com/express/usuario1');
    final names = dir.listSync().map((entity) => entity.path).join('\n');
    expect(names, isNot(contains('QaOfferHarness')));
  });
}

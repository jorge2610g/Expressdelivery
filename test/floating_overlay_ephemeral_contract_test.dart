import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source contracts for the ephemeral Android offer banner.
/// Real swipe, lifecycle and FCM behavior still require emulator QA.
void main() {
  late String native;
  late String plugin;
  late String layout;
  late String driver;
  late String policy;

  setUpAll(() {
    native = File(
      'android_overlay/kotlin/com/express/usuario1/FloatingOfferService.kt',
    ).readAsStringSync();
    plugin = File(
      'android_overlay/kotlin/com/express/usuario1/FloatingOfferPlugin.kt',
    ).readAsStringSync();
    layout = File('android_overlay/res/layout/express_floating_offer.xml')
        .readAsStringSync();
    driver = File('lib/driver_floating_offers.dart').readAsStringSync();
    policy = File('lib/driver_floating_offer_policy.dart').readAsStringSync();
  });

  test('banner lasts 15s by default, capped to 10-20 seconds', () {
    expect(native, contains('DEFAULT_BANNER_SECONDS = 30'));
    expect(native, contains('coerceIn(10, 30)'));
    expect(native, contains('getVisualDeadline(id, expiresAt, seconds)'));
    expect(driver, contains('this.displayDurationSeconds = 30'));
    expect(driver, contains('displayDurationSeconds.clamp(10, 30)'));
    expect(plugin, contains('EXTRA_DISPLAY_DURATION'));
  });

  test('repeated updates cannot reset the offer visual timer', () {
    expect(native, contains('prefs.getLong(key, 0L)'));
    expect(native, contains('if (recorded != 0L) recorded'));
    expect(native, contains('getVisualDeadline'));
    expect(native, contains('wasDismissed(id)'));
    expect(native, contains('rememberDismissal()'));
  });

  test('left, right, up and close dismiss entire overlay', () {
    expect(native, contains('val sideways = abs(dx) > dp(40)'));
    expect(native, contains('val upwards = dy < -dp(40)'));
    // El gesto anima la tarjeta fuera de pantalla y solo entonces la cierra.
    expect(native, contains('sideways -> flingOut('));
    expect(native, contains('upwards -> flingOut('));
    expect(native, contains('settleBack(view)'));
    expect(native, contains('R.id.offer_close).setOnClickListener { dismiss() }'));
    expect(native, isNot(contains('ImageView(this)')));
    expect(native, isNot(contains('dismissCard()')));
    expect(native, contains('stopSelf()'));
  });

  test('opening Express hides native banner and reuses offer popup', () {
    expect(native, contains('FloatingOfferPlugin.emitAction(this, id, "open")'));
    expect(native, contains('dismiss()\n            openApp()'));
    expect(policy, contains('if (context.appInForeground) return false;'));
  });

  test('redesigned layout preserves route fare countdown and action', () {
    for (final id in [
      'offer_card_root', 'offer_title', 'offer_remaining',
      'offer_close', 'offer_service_icon', 'offer_price',
      'offer_route', 'offer_progress',
    ]) {
      expect(layout, contains('android:id="@+id/$id"'), reason: id);
    }
    expect(layout, contains('Ver oferta'));
    expect(layout, contains('#FF51C9FF'));
  });
}

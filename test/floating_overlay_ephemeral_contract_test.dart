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
  late String home;

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
    home = File('lib/video_style_home.dart').readAsStringSync();
  });

  test('banner lasts up to 30s, without extending server expiry', () {
    expect(native, contains('DEFAULT_BANNER_SECONDS = 30'));
    expect(native, contains('coerceIn(10, 30)'));
    expect(native, contains('getVisualDeadline(id, expiresAt, seconds)'));
    expect(driver, contains('this.displayDurationSeconds = 30'));
    expect(driver, contains('displayDurationSeconds.clamp(10, 30)'));
    expect(plugin, contains('EXTRA_DISPLAY_DURATION'));
    expect(plugin, contains('?.toInt() ?: 30'));
  });

  test('repeated updates cannot reset the offer visual timer', () {
    expect(native, contains('prefs.getLong(key, 0L)'));
    expect(native, contains('if (recorded != 0L) recorded'));
    expect(native, contains('getVisualDeadline'));
    expect(native, contains('wasDismissed(id)'));
    expect(native, contains('rememberDismissal()'));
  });

  test('backend cancellation or assignment closes only the matching native bar', () {
    expect(native, contains('hideActiveIfOfferId(offerId: String)'));
    expect(native, contains('if (active.offerId == offerId) active.hide()'));
    expect(plugin, contains('"activeOfferId"'));
    expect(plugin, contains('"hideIfOfferId"'));
    expect(driver, contains("invokeMethod<String>('activeOfferId')"));
    expect(driver, contains("invokeMethod<bool>("));
    expect(driver, contains('invalidateOffer(String offerId)'));
    expect(home, contains("updatedStatus != 'searching'"));
    expect(home, contains("updatedStatus != 'offers_received'"));
    expect(home, contains('_floatingOffers.invalidateOffer(changedId)'));
  });

  test('background bar revalidates status with authenticated server read', () {
    expect(home, contains("from('ride_requests')"));
    expect(home, contains("select('status,expires_at,channel')"));
    expect(home, contains('Timer.periodic(const Duration(seconds: 3)'));
    expect(home, contains('_checkActiveDriverFloatingBar()'));
    expect(home, contains("status == 'searching'"));
    expect(home, contains("status == 'offers_received'"));
    expect(home, contains('_driverFloatingBarValidityTimer?.cancel()'));
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

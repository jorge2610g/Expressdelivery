import 'package:expressdelivery/driver_floating_offer_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 12);
  final offer = FloatingOfferCandidate(
    service: FloatingOfferService.taxi,
    expiresAt: now.add(const Duration(seconds: 30)),
  );

  FloatingOfferContext ctx({
    bool setting = true,
    bool permission = true,
    bool online = true,
    bool available = true,
    bool foreground = false,
    DateTime? at,
  }) =>
      FloatingOfferContext(
        settingEnabled: setting,
        overlayPermissionGranted: permission,
        driverOnline: online,
        driverAvailable: available,
        appInForeground: foreground,
        now: at ?? now,
      );

  test('shows only when every condition holds', () {
    expect(shouldShowFloatingOffer(ctx(), offer), isTrue);
  });

  test('never shows without the voluntary setting or the permission', () {
    expect(shouldShowFloatingOffer(ctx(setting: false), offer), isFalse);
    expect(shouldShowFloatingOffer(ctx(permission: false), offer), isFalse);
  });

  test('never shows while offline or unavailable', () {
    expect(shouldShowFloatingOffer(ctx(online: false), offer), isFalse);
    expect(shouldShowFloatingOffer(ctx(available: false), offer), isFalse);
  });

  test('never shows in foreground, where the app shows its own cards', () {
    expect(shouldShowFloatingOffer(ctx(foreground: true), offer), isFalse);
  });

  test('never shows an expired or missing offer', () {
    expect(shouldShowFloatingOffer(ctx(at: offer.expiresAt), offer), isFalse);
    expect(shouldShowFloatingOffer(ctx(), null), isFalse);
  });
}

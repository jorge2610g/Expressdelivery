import 'package:expressdelivery/driver_offer_notification_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 16, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a shown offer suppresses its late local notification', () async {
    await markDriverOfferSuppressed('ride-1', now: now);
    expect(await isDriverOfferSuppressed('ride-1', now: now), isTrue);
    expect(
      await isDriverOfferSuppressed(
        'ride-1',
        now: now.add(driverOfferSuppressionWindow - const Duration(seconds: 1)),
      ),
      isTrue,
    );
  });

  test('suppression expires after the window', () async {
    await markDriverOfferSuppressed('ride-1', now: now);
    expect(
      await isDriverOfferSuppressed(
        'ride-1',
        now: now.add(driverOfferSuppressionWindow),
      ),
      isFalse,
    );
  });

  test('other offers are never suppressed', () async {
    await markDriverOfferSuppressed('ride-1', now: now);
    expect(await isDriverOfferSuppressed('ride-2', now: now), isFalse);
  });

  test('empty ride ids are ignored and never suppressed', () async {
    await markDriverOfferSuppressed('', now: now);
    expect(await isDriverOfferSuppressed('', now: now), isFalse);
  });
}

import 'package:expressdelivery/driver_floating_offer_policy.dart';
import 'package:expressdelivery/driver_floating_offers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('express/floating_offers');
  final now = DateTime.utc(2026, 10, 16, 12);
  final offer = FloatingOfferCard(
    offerId: 'ride-1',
    service: FloatingOfferService.taxi,
    priceLabel: r'$3.500',
    routeLabel: 'Centro → Aeropuerto',
    expiresAt: now.add(const Duration(seconds: 30)),
  );

  late bool showResult;
  late List<String> shownIds;

  setUp(() {
    showResult = true;
    shownIds = <String>[];
    SharedPreferences.setMockInitialValues(
      <String, Object>{driverFloatingOfferSettingKey: true},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'hasPermission') return true;
      if (call.method == 'show') return showResult;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  DriverFloatingOfferController controller() => DriverFloatingOfferController(
        bridge: DriverFloatingOfferBridge(),
        settings: const DriverFloatingOfferSettings(),
        onShown: shownIds.add,
      );

  Future<void> sync(DriverFloatingOfferController c) => c.sync(
        offer: offer,
        driverOnline: true,
        driverAvailable: true,
        appInForeground: false,
        now: now,
      );

  test('reports the offer once when Android confirms the floating bar',
      () async {
    final c = controller();
    await sync(c);
    expect(shownIds, <String>['ride-1']);
  });

  test('does not report when Android refuses the floating bar', () async {
    showResult = false;
    final c = controller();
    await sync(c);
    expect(shownIds, isEmpty);
  });

  test('does not report again for the same offer on repeated syncs', () async {
    final c = controller();
    await sync(c);
    await sync(c);
    expect(shownIds, <String>['ride-1']);
  });
}

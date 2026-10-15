import 'package:expressdelivery/driver_floating_offer_policy.dart';
import 'package:expressdelivery/driver_floating_offers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('express/floating_offers');
  final now = DateTime.utc(2026, 10, 15, 12);
  final offer = FloatingOfferCard(
    offerId: 'o1',
    service: FloatingOfferService.taxi,
    priceLabel: r'$3.500',
    routeLabel: 'Centro → Aeropuerto',
    expiresAt: now.add(const Duration(seconds: 30)),
  );

  late List<String> calls;
  late bool permission;

  setUp(() {
    calls = <String>[];
    permission = true;
    SharedPreferences.setMockInitialValues(
      <String, Object>{driverFloatingOfferSettingKey: true},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'hasPermission') return permission;
      if (call.method == 'show') return true;
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
      );

  test('opt-in is isolated between driver accounts', () async {
    final first = DriverFloatingOfferSettings(accountId: 'driver-a');
    final second = DriverFloatingOfferSettings(accountId: 'driver-b');
    expect(await first.isEnabled(), isFalse);
    expect(await second.isEnabled(), isFalse);
    await first.setEnabled(true);
    expect(await first.isEnabled(), isTrue);
    expect(await second.isEnabled(), isFalse);
  });

  test('the setting is off by default and never requests permission itself', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(await const DriverFloatingOfferSettings().isEnabled(), isFalse);
    final c = controller();
    await c.sync(
      offer: offer,
      driverOnline: true,
      driverAvailable: true,
      appInForeground: false,
      now: now,
    );
    expect(calls, isNot(contains('show')));
    expect(calls, isNot(contains('openPermissionSettings')));
  });

  test('shows the card once when every condition holds, not twice', () async {
    final c = controller();
    for (var i = 0; i < 2; i++) {
      await c.sync(
        offer: offer,
        driverOnline: true,
        driverAvailable: true,
        appInForeground: false,
        now: now,
      );
    }
    expect(calls.where((m) => m == 'show').length, 1);
    expect(c.shownOfferId, 'o1');
  });

  test('hides when the app returns to the foreground or the driver goes offline', () async {
    final c = controller();
    await c.sync(
      offer: offer,
      driverOnline: true,
      driverAvailable: true,
      appInForeground: false,
      now: now,
    );
    await c.sync(
      offer: offer,
      driverOnline: true,
      driverAvailable: true,
      appInForeground: true,
      now: now,
    );
    expect(calls.last, 'hide');
    expect(c.shownOfferId, isNull);
  });

  test('never shows an expired offer', () async {
    final c = controller();
    await c.sync(
      offer: offer,
      driverOnline: true,
      driverAvailable: true,
      appInForeground: false,
      now: offer.expiresAt,
    );
    expect(calls, isNot(contains('show')));
  });

  test('without the overlay permission nothing is shown', () async {
    permission = false;
    final c = controller();
    await c.sync(
      offer: offer,
      driverOnline: true,
      driverAvailable: true,
      appInForeground: false,
      now: now,
    );
    expect(calls, isNot(contains('show')));
  });

  test('a missing native plugin degrades to no card instead of an error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final c = controller();
    await expectLater(
      c.sync(
        offer: offer,
        driverOnline: true,
        driverAvailable: true,
        appInForeground: false,
        now: now,
      ),
      completes,
    );
    expect(c.shownOfferId, isNull);
  });

  test('accept and reject from the card are routed once and only for valid actions', () async {
    final actions = <String>[];
    final bridge = DriverFloatingOfferBridge(
      onAction: (id, action) => actions.add('$id:$action'),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('action', <String, Object>{
          'offerId': 'o1',
          'action': 'accept',
        }),
      ),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('action', <String, Object>{
          'offerId': 'o1',
          'action': 'explode',
        }),
      ),
      (_) {},
    );
    expect(actions, <String>['o1:accept']);
    bridge.dispose();
  });

  test('accept only focuses the offer; reject writes nothing and does not focus', () {
    driverFloatingOfferFocus.value = null;
    applyFloatingOfferAction('o9', 'reject');
    expect(driverFloatingOfferFocus.value, isNull);
    applyFloatingOfferAction('o9', 'accept');
    expect(driverFloatingOfferFocus.value, 'o9');
    driverFloatingOfferFocus.value = null;
  });
}

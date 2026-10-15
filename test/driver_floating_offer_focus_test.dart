import 'package:expressdelivery/driver_floating_offer_focus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 12);
  final fresh = now.add(const Duration(seconds: 30)).toIso8601String();
  final past = now.subtract(const Duration(seconds: 1)).toIso8601String();
  final rides = <Map<String, dynamic>>[
    {'id': 'r1', 'expires_at': fresh},
    {'id': 'r2', 'expires_at': past},
  ];
  final deliveries = <Map<String, dynamic>>[
    {'id': 'd1', 'expires_at': fresh},
  ];

  FloatingOfferFocusTarget? resolve({
    String? id,
    bool online = true,
    DateTime? at,
  }) =>
      resolveFloatingOfferFocus(
        offerId: id,
        rides: rides,
        deliveries: deliveries,
        driverOnline: online,
        now: at ?? now,
      );

  test('a valid Taxi offer resolves to the Taxi kind', () {
    final t = resolve(id: 'r1');
    expect(t?.kind, FloatingOfferFocusKind.taxi);
    expect(t?.item['id'], 'r1');
  });

  test('a valid Envíos offer resolves to the delivery kind', () {
    expect(resolve(id: 'd1')?.kind, FloatingOfferFocusKind.delivery);
  });

  test('an expired offer is never opened', () {
    expect(resolve(id: 'r2'), isNull);
  });

  test('an offer that is no longer in the fresh list is dropped', () {
    expect(resolve(id: 'gone'), isNull);
  });

  test('an offline driver never opens an offer from the card', () {
    expect(resolve(id: 'r1', online: false), isNull);
  });

  test('an empty or missing id opens nothing', () {
    expect(resolve(id: null), isNull);
    expect(resolve(id: ''), isNull);
  });

  test('an offer exactly at its expiry is treated as expired', () {
    expect(resolve(id: 'd1', at: DateTime.parse(fresh)), isNull);
  });
}

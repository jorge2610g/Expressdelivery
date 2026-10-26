import 'package:expressdelivery/driver_floating_offer_data.dart';
import 'package:expressdelivery/driver_floating_offer_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 16);
  String money(Object value, String currency) => '$currency $value';
  final ride = <String, dynamic>{
    'id': 'r1',
    'expires_at': now.add(const Duration(minutes: 2)).toIso8601String(),
    'status': 'pending',
    'proposed_fare': 3500,
    'currency': 'CLP',
    'pickup_address': 'Centro',
    'destination_address': 'Aeropuerto',
  };
  final delivery = <String, dynamic>{
    'id': 'd1',
    // Real delivery_requests rows do not have expires_at.
    'created_at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
    'status': 'searching',
    'proposed_fare': 2400,
    'currency': 'CLP',
    'pickup_address': 'Sucursal',
    'dropoff_address': 'Plaza Central, Calle Sucre 124',
  };

  test('Taxi uses its actual price, currency, route and expiry', () {
    final card = driverFloatingCardFromRow(
        ride, FloatingOfferService.taxi, now, formatPrice: money)!;
    expect(card.offerId, 'r1');
    expect(card.priceLabel, 'CLP 3500');
    expect(card.routeLabel, 'Centro → Aeropuerto');
    expect(card.expiresAt.isAfter(now), true);
  });

  test('ride_requests with service_mode parcel use Envíos and original route', () {
    final card = firstDriverFloatingCard(
      rides: [{...ride, 'service_mode': 'parcel'}],
      deliveries: [], now: now, formatPrice: money,
    )!;
    expect(card.service, FloatingOfferService.delivery);
    expect(card.routeLabel, 'Centro → Aeropuerto');
  });

  test('Envíos uses a descriptive dropoff, not the Taxi destination field', () {
    final card = driverFloatingCardFromRow(
        delivery, FloatingOfferService.delivery, now, formatPrice: money)!;
    expect(card.routeLabel, 'Sucursal → Plaza Central, Calle Sucre 124');
    expect(card.priceLabel, 'CLP 2400');
    expect(card.expiresAt, now.add(const Duration(minutes: 2)));
  });

  test('Envíos card never survives three minutes without a server expiry', () {
    final stale = {...delivery,
      'created_at': now.subtract(const Duration(minutes: 3)).toIso8601String()};
    expect(driverFloatingCardFromRow(
        stale, FloatingOfferService.delivery, now, formatPrice: money), isNull);
    expect(driverFloatingOfferMatches(
        stale, 'd1', FloatingOfferService.delivery, now), false);
  });

  test('rejects expired, cancelled or malformed rows', () {
    for (final bad in <Map<String, dynamic>>[
      {...ride, 'expires_at': null},
      {...ride, 'id': ''},
      {...ride, 'expires_at': now.toIso8601String()},
      {...ride, 'status': 'cancelled'},
      {...ride, 'status': 'assigned'},
    ]) {
      expect(driverFloatingCardFromRow(
          bad, FloatingOfferService.taxi, now, formatPrice: money), isNull);
    }
  });

  test('uses safe address labels when route, currency or price is missing', () {
    final card = driverFloatingCardFromRow(
        {...ride, 'currency': null, 'pickup_address': null,
         'destination_address': ''},
        FloatingOfferService.taxi, now, formatPrice: money)!;
    expect(card.priceLabel, 'Precio no disponible');
    expect(card.routeLabel,
        'Ubicación de recogida → Ubicación de destino');
  });

  test('restaurant marketplace deliveries are excluded from Express conductor', () {
    expect(driverFloatingCardFromRow({...delivery, 'marketplace_order_id': 'm1'},
        FloatingOfferService.delivery, now, formatPrice: money), isNull);
  });

  test('selects first eligible offer after an expired Taxi row', () {
    expect(firstDriverFloatingCard(
      rides: [{...ride, 'expires_at': now.toIso8601String()}],
      deliveries: [delivery], now: now, formatPrice: money,
    )?.offerId, 'd1');
  });

  test('a tap is recoverable for 2 minutes but never indefinitely', () {
    final accepted = now;
    expect(driverFloatingActionIsRecent(accepted,
        now.add(const Duration(seconds: 3))), isTrue);
    expect(driverFloatingActionIsRecent(accepted,
        now.add(const Duration(seconds: 90))), isTrue);
    expect(driverFloatingActionIsRecent(accepted,
        now.add(const Duration(seconds: 121))), isFalse);
    expect(driverFloatingActionIsRecent(accepted,
        now.subtract(const Duration(seconds: 1))), isFalse);
  });

  test('a newly expired offer is rejected by revalidation', () {
    expect(driverFloatingOfferMatches(
        ride, 'r1', FloatingOfferService.taxi, now), true);
    expect(driverFloatingOfferMatches(
        ride, 'r1', FloatingOfferService.taxi,
        now.add(const Duration(minutes: 3))), false);
  });
}

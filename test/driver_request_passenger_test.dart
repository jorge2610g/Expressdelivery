import 'package:expressdelivery/driver_floating_offer_data.dart';
import 'package:expressdelivery/driver_floating_offer_policy.dart';
import 'package:expressdelivery/driver_request_passenger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 16);
  String money(Object value, String currency) => '$currency $value';

  Map<String, dynamic> ride([Map<String, dynamic> extra = const {}]) =>
      <String, dynamic>{
        'id': 'r1',
        'expires_at': now.add(const Duration(minutes: 2)).toIso8601String(),
        'status': 'pending',
        'proposed_fare': 15,
        'currency': 'BOB',
        'pickup_address': 'Centro',
        'destination_address': 'Aeropuerto',
        'passenger_id': 'p1',
        ...extra,
      };

  test('sin datos del pasajero (respuesta anterior a la migración) no inventa nada', () {
    expect(DriverRequestPassenger.fromRide(ride()), isNull);
  });

  test('primer nombre, calificación con conteo y foto https', () {
    final p = DriverRequestPassenger.fromRide(ride({
      'passenger_first_name': 'Anita',
      'passenger_avatar_url': 'https://lh3.googleusercontent.com/a/x=s96-c',
      'passenger_rating': 3.33,
      'passenger_rating_count': 3,
    }))!;
    expect(p.displayName, 'Anita');
    expect(p.avatarUrl, startsWith('https://'));
    expect(p.ratingLabel, '★ 3.3 · 3 calificaciones');
    expect(p.floatingSummary, 'Anita ★ 3.3 (3)');
  });

  test('sin nombre ni calificaciones: texto neutro y sin estrella', () {
    final p = DriverRequestPassenger.fromRide(ride({
      'passenger_first_name': null,
      'passenger_avatar_url': null,
      'passenger_rating': null,
      'passenger_rating_count': 0,
    }))!;
    expect(p.displayName, 'Pasajero');
    expect(p.ratingLabel, 'Sin calificaciones aún');
    expect(p.floatingSummary, 'Pasajero');
    expect(p.avatarUrl, isNull);
  });

  test('una sola calificación usa singular', () {
    final p = DriverRequestPassenger.fromRide(ride({
      'passenger_first_name': 'Jhon',
      'passenger_rating': 5,
      'passenger_rating_count': 1,
    }))!;
    expect(p.ratingLabel, '★ 5.0 · 1 calificación');
  });

  test('una foto que no es http(s) se descarta', () {
    final p = DriverRequestPassenger.fromRide(ride({
      'passenger_first_name': 'Ana',
      'passenger_avatar_url': 'javascript:alert(1)',
      'passenger_rating_count': 0,
    }))!;
    expect(p.avatarUrl, isNull);
  });

  test('la tarjeta flotante antepone nombre y calificación al trayecto', () {
    final card = driverFloatingCardFromRow(
      ride({
        'passenger_first_name': 'Anita',
        'passenger_rating': 3.33,
        'passenger_rating_count': 3,
      }),
      FloatingOfferService.taxi,
      now,
      formatPrice: money,
    )!;
    expect(card.routeLabel, 'Anita ★ 3.3 (3) · Centro → Aeropuerto');
    expect(card.toMap().keys.any((k) => k.toLowerCase().contains('phone')),
        isFalse);
  });

  test('pedidos de restaurante no muestran datos del cliente en la flotante', () {
    final card = driverFloatingCardFromRow(
      ride({
        '_express_delivery': true,
        'passenger_first_name': 'Anita',
        'passenger_rating': 3.3,
        'passenger_rating_count': 3,
      }),
      FloatingOfferService.taxi,
      now,
      formatPrice: money,
    )!;
    expect(card.routeLabel, 'Centro → Aeropuerto');
  });
}

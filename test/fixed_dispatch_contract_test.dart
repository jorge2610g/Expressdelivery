import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:expressdelivery/fixed_dispatch_search_card.dart';

/// Precio fijo con asignación uno a uno (modo del servicio, apagado por defecto).
void main() {
  test('cuenta regresiva en formato mm:ss', () {
    expect(fixedDispatchClock(15), '00:15');
    expect(fixedDispatchClock(0), '00:00');
    expect(fixedDispatchClock(-3), '00:00');
    expect(fixedDispatchClock(75), '01:15');
  });

  test('conductor: acepta o rechaza, sin contraoferta', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains("ride['dispatch_style'] == 'sequential'"));
    expect(home, contains('acceptFixedDispatch('));
    expect(home, contains('declineFixedDispatch('));
    expect(home, contains('!fixedCoupon && !sequentialFixed'));
    expect(home, contains('fixed_attempt_expires_at'));
  });

  test('pasajero: precio fijo sin edición y búsqueda uno a uno', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains("fixedPrice: fareQuote['price_mode'] == 'fixed'"));
    expect(home, contains('FixedDispatchSearchCard('));
    expect(home, contains('couponApplied || fixedPrice ? null : onEdit'));
    final service = File('lib/services/express_service.dart').readAsStringSync();
    expect(service, contains('passenger_fixed_dispatch_state_v1'));
    expect(service, contains('passenger_fixed_dispatch_restart_v1'));
    expect(service, contains('driver_accept_fixed_dispatch_v1'));
    expect(service, contains('driver_decline_fixed_dispatch_v1'));
  });

  test('la tarjeta ofrece volver a buscar cuando nadie acepta', () {
    final card = File('lib/fixed_dispatch_search_card.dart').readAsStringSync();
    expect(card, contains('Volver a buscar'));
    expect(card, contains('El conductor está respondiendo'));
    expect(card, contains('restartFixedDispatch'));
  });
}

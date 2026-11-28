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
    expect(home, contains('fixedPrice: _fixedChosen'));
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
    expect(card, contains('Seguir buscando'));
    expect(card, contains('Esperando que el conductor acepte'));
    expect(card, contains('Este conductor no está disponible'));
    expect(card, contains('restartFixedDispatch'));
  });

  test('la búsqueda dura un minuto y pregunta si sigue o cancela', () {
    final card = File('lib/fixed_dispatch_search_card.dart').readAsStringSync();
    expect(card, contains('Buscando conductor cerca de ti'));
    expect(card, contains('¿Seguimos buscando conductor?'));
    expect(card, contains('window_seconds_left'));
    expect(card, contains("ValueKey('fixed-window-clock')"));
    expect(card, isNot(contains('conductores cerca')));
    expect(card, isNot(contains('No encontramos conductor por ahora')));
  });
  autoCancelContract();
}

void autoCancelContract() {
  test('si el pasajero no decide, el viaje se cancela solo con cuenta regresiva', () {
    final card = File('lib/fixed_dispatch_search_card.dart').readAsStringSync();
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(card, contains('Se cancelará automáticamente en'));
    expect(card, contains('decision_seconds_left'));
    expect(card, contains('widget.onExpired?.call()'));
    expect(home, contains('onFixedExpired: _cancelExpiredRideSilently'));
    expect(home, contains('onExpired: () => onFixedExpired('));
  });
}

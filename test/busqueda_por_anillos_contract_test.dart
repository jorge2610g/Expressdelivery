import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato de la búsqueda de conductores por anillos (1 km, 2 km, 3 km…).
void main() {
  late String migration;
  late String home;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20261116120000_busqueda_por_anillos.sql',
    ).readAsStringSync();
    home = File('lib/video_style_home.dart').readAsStringSync();
  });

  test('la solicitud empieza en el anillo inicial y se amplía solo sin oferta', () {
    expect(migration, contains("dispatch_mode = 'progressive'"));
    expect(migration, contains('dispatch_ring_seconds = 30'));
    expect(migration, contains('progressive_radius_step_km = 1'));
    expect(migration, contains('public.advance_ride_dispatch_rings()'));
    expect(migration, contains("'10 seconds'"));
    // No se amplía si ya hay una oferta pendiente.
    expect(migration, contains("o.status = 'pending'"));
  });

  test('el aviso inicial y el de cada anillo usan solo la distancia del anillo', () {
    expect(migration, contains('public.ride_dispatch_candidates(p_request, p_min_km, p_max_km)'));
    expect(migration, contains('dp.latitude is not null'));
    expect(migration, contains('public.notify_ride_candidates(r, r.dispatch_ring_km, v_new)'));
  });

  test('la lista muestra todo lo buscando dentro del anillo actual, sin ventana de tiempo', () {
    // Lo que el conductor ya vio (pop-up) se queda en su lista mientras la solicitud busca.
    expect(migration, isNot(contains('dispatch_ring_started_at >')));
    expect(migration, contains('or r.dispatch_ring_km is not null'));
  });

  test('el pop-up no tiene tope de 10 km cuando hay anillos', () {
    expect(home, contains("if (ride['dispatch_ring_km'] != null) return true;"));
  });

  test('la lista del conductor usa su anillo y ordena por cercanía', () {
    expect(migration, contains('coalesce(r.dispatch_ring_km, v_radius)'));
    expect(migration, contains('order by pickup_distance_sort asc, r.created_at asc'));
    // Sin ubicación no se muestra nada.
    expect(migration, contains('if v_lat is null or v_lng is null then'));
  });

  test('las ofertas al pasajero se ordenan por distancia y la llevan', () {
    expect(migration, contains("'driver_distance_km', dist.km"));
    expect(migration, contains('order by dist.km asc nulls last, o.created_at asc'));
  });

  test('el conductor solo puede ofertar dentro de su anillo, en la base', () {
    expect(migration, contains('before insert or update of proposed_fare on public.driver_offers'));
    expect(migration, contains('Esta solicitud no está en tu radio actual.'));
    expect(migration, contains('v_km > v_req.dispatch_ring_km + 0.2'));
  });

  test('la tarjeta de oferta muestra a cuántos km está el conductor', () {
    expect(home, contains("final driverKm = asDouble(offer['driver_distance_km']);"));
    expect(home, contains("'a \${driverKm.toStringAsFixed(1)} km de ti'"));
  });

  test('el texto de búsqueda del pasajero no cambia', () {
    expect(home, contains('Buscando conductor'));
  });
}

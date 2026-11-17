import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato del flujo SOS que desbloquea el servicio. Es una comprobación de
/// fuente: la lógica SQL se probó en PostgreSQL 16 local con copias de las
/// funciones y tablas (ver la descripción del PR). El desbloqueo real en
/// teléfono no se prueba aquí.
void main() {
  const migrationPath =
      'supabase/migrations/20261107110000_emergency_resolve_flow.sql';
  late String migration;
  late String home;

  setUpAll(() {
    migration = File(migrationPath).readAsStringSync();
    home = File('lib/video_style_home.dart').readAsStringSync();
  });

  group('RPC admin_resolve_emergency_v3', () {
    test('es una función nueva, solo para authenticated', () {
      expect(
        migration,
        contains('create or replace function public.admin_resolve_emergency_v3('),
      );
      expect(migration, contains('security definer'));
      expect(migration, contains('set search_path = public'));
      expect(
        migration,
        contains(
          'revoke execute on function public.admin_resolve_emergency_v3(uuid, text) from public, anon;',
        ),
      );
      expect(
        migration,
        contains(
          'grant execute on function public.admin_resolve_emergency_v3(uuid, text) to authenticated;',
        ),
      );
    });

    test('no reemplaza las versiones anteriores', () {
      expect(
        migration,
        isNot(contains('function public.admin_resolve_emergency_v2')),
      );
      expect(
        migration,
        isNot(contains('function public.admin_resolve_emergency(')),
      );
    });

    test('exige super_admin, entorno permitido y la misma cuenta de entorno', () {
      expect(migration, contains('admin_assert_environment(p_channel)'));
      expect(migration, contains('if not public.is_admin() then'));
      expect(
        migration,
        contains("perform public.admin_operator_assert_module('dashboard');"),
      );
      expect(
        migration,
        contains(
          'perform public.admin_assert_target_environment(v_emergency.user_id, v_channel);',
        ),
      );
    });

    test('es idempotente: una alerta ya cerrada no cambia el viaje ni avisa', () {
      expect(migration, contains("if v_emergency.status <> 'active' then"));
      expect(migration, contains("'already_closed', true"));
    });

    test('devuelve el viaje a su estado anterior solo desde emergency', () {
      expect(
        migration,
        contains("if v_trip.status = 'emergency' and v_other_open_alerts = 0 then"),
      );
      expect(migration, contains("h.status = 'emergency'"));
      expect(migration, contains("coalesce(v_restore_status, 'in_progress')"));
      expect(migration, contains('auth.uid()'));
      expect(
        migration,
        contains('insert into public.trip_status_history (trip_id, status, changed_by)'),
      );
    });

    test('no restaura a estados terminales ni a emergencia', () {
      expect(
        migration,
        contains(
          "h.status in ('driver_assigned', 'driver_arriving', 'driver_waiting', 'in_progress')",
        ),
      );
    });

    test('avisa a pasajero y conductor con metadata del viaje', () {
      expect(migration, contains("'Alerta resuelta'"));
      expect(migration, contains("'trip_id', v_trip.id"));
      expect(migration, contains("v_parties := array[v_trip.passenger_id, v_trip.driver_id];"));
      expect(migration, contains("v_type := 'trip_status';"));
    });

    test('un envío no modifica delivery_requests', () {
      expect(migration, isNot(contains('update public.delivery_requests')));
      expect(migration, contains("v_type := 'delivery_status';"));
    });

    test('registra la acción en la auditoría con el entorno', () {
      expect(migration, contains("perform public.admin_log_action("));
      expect(migration, contains("'environment', v_channel"));
    });
  });

  group('refresco del conductor mientras el viaje está en emergencia', () {
    test('consulta cada 4 s y solo cuando el estado es emergency', () {
      expect(home, contains('_driverEmergencyRefreshTimer = Timer.periodic('));
      expect(home, contains('const Duration(seconds: 4)'));
      expect(
        home,
        contains(
          "cachedData?.activeTrip?['status']?.toString() != 'emergency'",
        ),
      );
    });

    test('el temporizador se cancela al salir de la pantalla', () {
      expect(home, contains('_driverEmergencyRefreshTimer?.cancel();'));
    });
  });

  group('refresco del pasajero', () {
    test('el estado del viaje se consulta cada 3 s y actualiza la pantalla', () {
      expect(
        home,
        contains(
          'passengerCriticalStateTimer =\n        Timer.periodic(const Duration(seconds: 3), (_) {',
        ),
      );
      expect(home, contains('passengerActiveTripLiveState()'));
      expect(home, contains("if (beforeActiveTripStatus != nextTripStatus) panelRevision++;"));
    });
  });

  group('aviso de alerta sin bloquear los botones de seguridad', () {
    test('la tarjeta del conductor muestra el aviso en emergencia', () {
      expect(home, contains("if (status == 'emergency') ...["));
      expect(home, contains('_SosPausedNotice(parcel: isParcel)'));
      expect(home, contains('Llamar y chat siguen disponibles.'));
    });

    test('el pasajero conserva Llamar y Compartir durante la alerta', () {
      expect(
        home,
        contains('Llamar y compartir siguen disponibles.'),
      );
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:expressdelivery/passenger_offer_backup_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('respaldo de ofertas', () {
    test('el respaldo corre cada 4 segundos, no cada segundo', () {
      expect(passengerOfferBackupInterval, const Duration(seconds: 4));
      expect(passengerOfferBackupInterval, isNot(const Duration(seconds: 1)));
    });

    test('sin tiempo real previo, el respaldo sí consulta', () {
      expect(
        passengerOfferBackupDue(lastRealtimeAt: null, now: DateTime(2026)),
        isTrue,
      );
    });

    test('con tiempo real reciente (menos de 5 s), el respaldo no consulta', () {
      final now = DateTime(2026, 11, 2, 10);
      expect(
        passengerOfferBackupDue(
          lastRealtimeAt: now.subtract(const Duration(seconds: 4)),
          now: now,
        ),
        isFalse,
      );
    });

    test('con el tiempo real en silencio 5 s o más, el respaldo consulta', () {
      final now = DateTime(2026, 11, 2, 10);
      expect(
        passengerOfferBackupDue(
          lastRealtimeAt: now.subtract(const Duration(seconds: 5)),
          now: now,
        ),
        isTrue,
      );
    });

    test('el temporizador del respaldo usa la constante, sin 1 s fijo', () {
      final source = File('lib/video_style_home.dart').readAsStringSync();
      expect(source, contains('Timer.periodic(passengerOfferBackupInterval'));
      expect(
        source,
        isNot(contains('Timer.periodic(const Duration(milliseconds: 1000)')),
      );
      expect(source, contains('passengerOfferBackupDue('));
    });
  });

  group('lecturas en paralelo', () {
    test('mismos datos que en serie y cada lectura cae a su valor por defecto',
        () async {
      Future<int> count() async => 3;
      Future<List<Map<String, dynamic>>> viewers() async => [
            {'id': 'a'},
          ];

      final results = await Future.wait<Object>([
        count().catchError((Object _) => 0),
        viewers().catchError((Object _) => <Map<String, dynamic>>[]),
      ]);
      expect(results[0] as int, 3);
      expect(results[1] as List<Map<String, dynamic>>, [
        {'id': 'a'},
      ]);
    });

    test('si una lectura falla, la otra sigue y la fallida usa su valor',
        () async {
      Future<int> count() async => throw StateError('red');
      Future<List<Map<String, dynamic>>> viewers() async => [
            {'id': 'b'},
          ];

      final results = await Future.wait<Object>([
        count().catchError((Object _) => 0),
        viewers().catchError((Object _) => <Map<String, dynamic>>[]),
      ]);
      expect(results[0] as int, 0);
      expect(results[1] as List<Map<String, dynamic>>, [
        {'id': 'b'},
      ]);
    });

    test('las lecturas de perfil y vehículo corren a la vez', () async {
      final started = <String>[];
      final gateProfile = Completer<void>();
      final gateVehicle = Completer<void>();

      Future<Map<String, dynamic>?> profile() async {
        started.add('profile');
        await gateProfile.future;
        return {'name': 'p'};
      }

      Future<Map<String, dynamic>?> vehicle() async {
        started.add('vehicle');
        await gateVehicle.future;
        return {'plate': 'v'};
      }

      final pending = Future.wait<Object?>([
        profile().catchError((Object _) => null),
        vehicle().catchError((Object _) => null),
      ]);
      await Future<void>.delayed(Duration.zero);
      // Ambas empezaron antes de que termine ninguna.
      expect(started, ['profile', 'vehicle']);

      gateProfile.complete();
      gateVehicle.complete();
      final results = await pending;
      expect(results[0] as Map<String, dynamic>?, {'name': 'p'});
      expect(results[1] as Map<String, dynamic>?, {'plate': 'v'});
    });
  });
}

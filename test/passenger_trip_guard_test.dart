import 'dart:io';

import 'package:expressdelivery/passenger_trip_guard.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> trip(String id, String status) => {
      'id': id,
      'status': status,
    };

void main() {
  group('finished trips never resurrect as active', () {
    test('an in-progress trip stays visible until it finishes', () {
      final guard = PassengerFinishedTrips();
      final visible = guard.visibleActiveTrip(trip('T1', 'in_progress'));

      expect(visible?['id'], 'T1');
    });

    test('a stale in-progress snapshot after completion is ignored', () {
      final guard = PassengerFinishedTrips();
      guard.markFinished('T1');

      // Respuesta anterior a la finalización que llega después.
      expect(guard.visibleActiveTrip(trip('T1', 'in_progress')), isNull);
      expect(guard.visibleActiveTrip(trip('T1', 'driver_waiting')), isNull);
    });

    test('a completed status is terminal and remembered', () {
      final guard = PassengerFinishedTrips();

      expect(guard.visibleActiveTrip(trip('T2', 'completed')), isNull);
      expect(guard.isFinished('T2'), isTrue);
      expect(guard.visibleActiveTrip(trip('T2', 'in_progress')), isNull);
    });

    test('a cancelled trip is terminal too', () {
      final guard = PassengerFinishedTrips();

      expect(guard.visibleActiveTrip(trip('T3', 'cancelled')), isNull);
      expect(isTerminalTripStatus('cancelled'), isTrue);
    });

    test('a new trip is not affected by a finished one', () {
      final guard = PassengerFinishedTrips();
      guard.markFinished('T1');

      expect(guard.visibleActiveTrip(trip('T4', 'in_progress'))?['id'], 'T4');
    });

    test('out-of-order events keep the terminal state', () {
      final guard = PassengerFinishedTrips();
      final events = [
        trip('T5', 'in_progress'),
        trip('T5', 'completed'),
        trip('T5', 'in_progress'),
        trip('T5', 'driver_waiting'),
      ];
      final shown = events.map(guard.visibleActiveTrip).toList();

      expect(shown[0]?['id'], 'T5');
      expect(shown.sublist(1), everyElement(isNull));
    });

    test('a null live result marks the previously active trip as finished', () {
      final guard = PassengerFinishedTrips();
      guard.visibleActiveTrip(trip('T6', 'in_progress'));
      // El servidor ya no devuelve el viaje como activo.
      guard.markFinished('T6');

      expect(guard.visibleActiveTrip(trip('T6', 'in_progress')), isNull);
    });

    test('empty ids are never recorded', () {
      final guard = PassengerFinishedTrips();
      guard.markFinished(null);
      guard.markFinished('');

      expect(guard.isFinished(''), isFalse);
      expect(guard.visibleActiveTrip(null), isNull);
    });
  });

  group('rating prompt is claimed once per trip', () {
    test('first claim wins, repeats are refused across rebuilds', () {
      final gate = PassengerRatingPromptGate();

      expect(gate.claim('T1'), isTrue);
      expect(gate.claim('T1'), isFalse);
      expect(gate.claim('T1'), isFalse);
    });

    test('different trips each get their own prompt', () {
      final gate = PassengerRatingPromptGate();

      expect(gate.claim('T1'), isTrue);
      expect(gate.claim('T2'), isTrue);
    });

    test('process-wide gate survives a screen rebuild', () {
      // Una pantalla reconstruida usa la misma instancia del proceso.
      expect(passengerRatingPromptGate.claim('T-rebuild'), isTrue);
      expect(passengerRatingPromptGate.claim('T-rebuild'), isFalse);
    });

    test('a missing id never prompts', () {
      final gate = PassengerRatingPromptGate();

      expect(gate.claim(null), isFalse);
      expect(gate.claim(''), isFalse);
    });
  });

  group('passenger screen uses the shared guard', () {
    late String home;

    setUpAll(() {
      home = File('lib/video_style_home.dart').readAsStringSync();
    });

    test('the home state build reads active trips through the guard', () {
      expect(
        home,
        contains(
          'var activeTrip = passengerFinishedTrips.visibleActiveTrip(rawActiveTrip);',
        ),
      );
      expect(home, contains("import 'passenger_trip_guard.dart';"));
    });

    test('the live refresh marks a null result as finished', () {
      expect(
        home,
        contains('passengerFinishedTrips.markFinished(beforeActiveTripId);'),
      );
    });

    test('auto rating prompt is claimed through the process-wide gate', () {
      expect(
        home,
        contains('passengerRatingPromptGate.claim(tripId)'),
      );
    });
  });
}

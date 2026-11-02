import 'package:expressdelivery/passenger_read_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

Future<T> _ok<T>(T value) async => value;
Future<T> _fail<T>() async => throw StateError('red');

/// Mismo patrón que usa el home: el fallo se convierte en centinela.
Future<Object?> _guarded<T>(Future<T> future) => future.then<Object?>(
      (value) => value,
      onError: (Object _) => passengerReadFailed,
    );

void main() {
  test('si falla la lectura del vehículo, conserva el vehículo anterior',
      () async {
    final results = await Future.wait<Object?>([
      _guarded(_fail<Map<String, dynamic>?>()),
    ]);
    final vehicle = resolvePassengerRead<Map<String, dynamic>?>(
      results[0],
      previous: {'plate': 'ABC-123'},
      fallback: null,
    );
    expect(vehicle, {'plate': 'ABC-123'});
  });

  test('si falla viewers, conserva la lista anterior', () async {
    final results = await Future.wait<Object?>([
      _guarded(_fail<List<Map<String, dynamic>>>()),
    ]);
    final viewers = resolvePassengerRead<List<Map<String, dynamic>>>(
      results[0],
      previous: [
        {'id': 'v1'},
      ],
      fallback: <Map<String, dynamic>>[],
    );
    expect(viewers, [
      {'id': 'v1'},
    ]);
  });

  test('si falla el contador, conserva el valor anterior', () async {
    final results = await Future.wait<Object?>([_guarded(_fail<int>())]);
    expect(
      resolvePassengerRead<int>(results[0], previous: 4, fallback: 0),
      4,
    );
  });

  test('sin valor previo, un fallo usa el valor por defecto', () async {
    final results = await Future.wait<Object?>([_guarded(_fail<int>())]);
    expect(
      resolvePassengerRead<int>(results[0], previous: null, fallback: 0),
      0,
    );
  });

  test('una lectura correcta sin dato devuelve null y no el previo', () async {
    final results = await Future.wait<Object?>([
      _guarded(_ok<Map<String, dynamic>?>(null)),
    ]);
    expect(
      resolvePassengerRead<Map<String, dynamic>?>(
        results[0],
        previous: {'plate': 'ANTIGUO'},
        fallback: null,
      ),
      isNull,
    );
  });

  test('en paralelo, un fallo no cambia el dato de la otra lectura', () async {
    final results = await Future.wait<Object?>([
      _guarded(_fail<int>()),
      _guarded(_ok<List<Map<String, dynamic>>>([
        {'id': 'x'},
      ])),
    ]);
    expect(resolvePassengerRead<int>(results[0], previous: 2, fallback: 0), 2);
    expect(
      resolvePassengerRead<List<Map<String, dynamic>>>(
        results[1],
        previous: null,
        fallback: <Map<String, dynamic>>[],
      ),
      [
        {'id': 'x'},
      ],
    );
  });
}

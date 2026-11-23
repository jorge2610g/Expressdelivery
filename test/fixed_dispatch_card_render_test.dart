import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/fixed_dispatch_search_card.dart';
import 'package:expressdelivery/services/express_service.dart';

class _FakeService implements ExpressService {
  _FakeService(this.state);
  final Map<String, dynamic> state;

  @override
  Future<Map<String, dynamic>> fixedDispatchState(String rideId) async => state;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Map<String, dynamic> state,
    {VoidCallback? onExpired}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FixedDispatchSearchCard(
        service: _FakeService(state),
        ride: const {'id': 'r1'},
        onCancel: () {},
        onExpired: onExpired,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('terminado el minuto muestra la pregunta y la cuenta regresiva',
      (tester) async {
    await _pump(tester, {
      'mode': 'sequential',
      'ride_status': 'searching',
      'exhausted': true,
      'current': null,
      'window_seconds_left': 0,
      'decision_seconds_left': 25,
    });
    expect(find.text('¿Seguimos buscando conductor?'), findsOneWidget);
    expect(find.byKey(const ValueKey('fixed-decision-countdown')), findsOneWidget);
    expect(find.textContaining('Se cancelará automáticamente en'), findsOneWidget);
    expect(find.text('Seguir buscando'), findsOneWidget);
    expect(find.text('Cancelar viaje'), findsOneWidget);
    // Cierra los temporizadores de la tarjeta.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin respuesta del servidor aún muestra la cuenta de 30 s',
      (tester) async {
    await _pump(tester, {
      'mode': 'sequential',
      'ride_status': 'searching',
      'exhausted': true,
      'current': null,
    });
    expect(find.textContaining('Se cancelará automáticamente en 30 s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('si el servidor ya canceló el viaje, avisa para volver al inicio',
      (tester) async {
    var expired = 0;
    await _pump(tester, {
      'mode': 'sequential',
      'ride_status': 'cancelled',
      'exhausted': true,
      'current': null,
    }, onExpired: () => expired++);
    expect(expired, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

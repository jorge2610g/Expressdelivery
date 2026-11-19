import 'dart:io';

import 'package:expressdelivery/maintenance_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Envuelve la prueba en MaterialApp, como la app real.
Widget _app(Widget home) => MaterialApp(debugShowCheckedModeBanner: false, home: home);

/// El interruptor «Modo mantenimiento» del panel debe bloquear la app.
void main() {
  test('solo el valor true activa el mantenimiento', () {
    expect(maintenanceActiveFrom(<String, dynamic>{'maintenance_mode': true}), isTrue);
    expect(maintenanceActiveFrom(<String, dynamic>{'maintenance_mode': 'true'}), isTrue);
    expect(maintenanceActiveFrom(<String, dynamic>{'maintenance_mode': false}), isFalse);
    expect(maintenanceActiveFrom(<String, dynamic>{'maintenance_mode': null}), isFalse);
    expect(maintenanceActiveFrom(<String, dynamic>{}), isFalse);
  });

  test('usa el mensaje del panel o uno por defecto', () {
    expect(
      maintenanceMessageFrom(<String, dynamic>{'maintenance_message': '  Volvemos pronto  '}),
      'Volvemos pronto',
    );
    expect(
      maintenanceMessageFrom(<String, dynamic>{'maintenance_message': null}),
      kDefaultMaintenanceMessage,
    );
    expect(
      maintenanceMessageFrom(<String, dynamic>{'maintenance_message': '   '}),
      kDefaultMaintenanceMessage,
    );
  });

  testWidgets('sin mantenimiento la app se ve normal', (tester) async {
    await tester.pumpWidget(_app(
      MaintenanceGate(
        loader: ({bool forceRefresh = false}) async =>
            <String, dynamic>{'maintenance_mode': false},
        child: const Text('APP'),
      ),
    ));
    await tester.pump();
    expect(find.text('APP'), findsOneWidget);
    expect(find.text('Express está en mantenimiento'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con mantenimiento muestra el mensaje y mantiene la app montada', (tester) async {
    await tester.pumpWidget(_app(
      MaintenanceGate(
        loader: ({bool forceRefresh = false}) async => <String, dynamic>{
          'maintenance_mode': true,
          'maintenance_message': 'Volvemos a las 18:00',
        },
        child: const Text('APP'),
      ),
    ));
    await tester.pump();
    expect(find.text('Express está en mantenimiento'), findsOneWidget);
    expect(find.text('Volvemos a las 18:00'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    // La app sigue en el árbol debajo de la pantalla de mantenimiento.
    expect(find.text('APP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('si la consulta falla no bloquea la app', (tester) async {
    await tester.pumpWidget(_app(
      MaintenanceGate(
        loader: ({bool forceRefresh = false}) async {
          throw StateError('sin conexión');
        },
        child: const Text('APP'),
      ),
    ));
    await tester.pump();
    expect(find.text('Express está en mantenimiento'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Reintentar levanta el mantenimiento cuando se apaga el interruptor', (tester) async {
    var active = true;
    await tester.pumpWidget(_app(
      MaintenanceGate(
        loader: ({bool forceRefresh = false}) async =>
            <String, dynamic>{'maintenance_mode': active},
        child: const Text('APP'),
      ),
    ));
    await tester.pump();
    expect(find.text('Express está en mantenimiento'), findsOneWidget);

    active = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Express está en mantenimiento'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la consulta se repite cada intervalo y activa el mantenimiento', (tester) async {
    var active = false;
    var calls = 0;
    await tester.pumpWidget(_app(
      MaintenanceGate(
        interval: const Duration(minutes: 2),
        loader: ({bool forceRefresh = false}) async {
          calls++;
          return <String, dynamic>{'maintenance_mode': active};
        },
        child: const Text('APP'),
      ),
    ));
    await tester.pump();
    expect(find.text('Express está en mantenimiento'), findsNothing);
    final before = calls;

    active = true;
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(calls, greaterThan(before));
    expect(find.text('Express está en mantenimiento'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('la app pasa la puerta de mantenimiento por fuera de la de actualización', () {
    final main = File('lib/mobile_main.dart').readAsStringSync();
    final gate = main.indexOf('return MaintenanceGate(');
    final update = main.indexOf('AndroidReleaseUpdateGate(child: child');
    expect(gate, greaterThan(0));
    expect(update, greaterThan(gate));
    expect(main, contains("import 'maintenance_gate.dart';"));
  });
}

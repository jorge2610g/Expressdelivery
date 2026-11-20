import 'dart:io';

import 'package:expressdelivery/maintenance_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Envuelve la prueba en MaterialApp, como la app real.
Widget _app(Widget home) =>
    MaterialApp(debugShowCheckedModeBanner: false, home: home);

const _title = 'Express está en mantenimiento';

/// Puerta de mantenimiento con el entorno ya reconocido: sesión de Producción.
MaintenanceGate _gate({
  required MaintenanceSettingsLoader loader,
  Widget child = const Text('APP'),
  ValueNotifier<bool>? preview,
  ValueNotifier<bool>? resolved,
  Future<void> Function()? onSignOut,
  Duration interval = const Duration(minutes: 2),
}) {
  return MaintenanceGate(
    previewListenable: preview ?? ValueNotifier<bool>(false),
    resolvedListenable: resolved ?? ValueNotifier<bool>(true),
    onSignOut: onSignOut,
    interval: interval,
    loader: loader,
    child: child,
  );
}

MaintenanceSettingsLoader _settings(bool Function() active, [String? message]) {
  return ({bool forceRefresh = false}) async => <String, dynamic>{
    'maintenance_mode': active(),
    'maintenance_message': message,
  };
}

/// El mantenimiento del panel bloquea solo a Producción y deja cerrar sesión.
void main() {
  test('solo el valor true activa el mantenimiento', () {
    expect(
      maintenanceActiveFrom(<String, dynamic>{'maintenance_mode': true}),
      isTrue,
    );
    expect(
      maintenanceActiveFrom(<String, dynamic>{'maintenance_mode': 'true'}),
      isTrue,
    );
    expect(
      maintenanceActiveFrom(<String, dynamic>{'maintenance_mode': false}),
      isFalse,
    );
    expect(
      maintenanceActiveFrom(<String, dynamic>{'maintenance_mode': null}),
      isFalse,
    );
    expect(maintenanceActiveFrom(<String, dynamic>{}), isFalse);
  });

  test('usa el mensaje del panel o uno por defecto', () {
    expect(
      maintenanceMessageFrom(<String, dynamic>{
        'maintenance_message': '  Volvemos pronto  ',
      }),
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
    await tester.pumpWidget(_app(_gate(loader: _settings(() => false))));
    await tester.pump();
    expect(find.text('APP'), findsOneWidget);
    expect(find.text(_title), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en Producción con mantenimiento muestra el mensaje y mantiene la app montada', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_gate(loader: _settings(() => true, 'Volvemos a las 18:00'))),
    );
    await tester.pump();
    expect(find.text(_title), findsOneWidget);
    expect(find.text('Volvemos a las 18:00'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('APP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('si la consulta falla no bloquea la app', (tester) async {
    await tester.pumpWidget(
      _app(
        _gate(
          loader: ({bool forceRefresh = false}) async {
            throw StateError('sin conexión');
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_title), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Reintentar levanta el mantenimiento cuando se apaga el interruptor', (
    tester,
  ) async {
    var active = true;
    await tester.pumpWidget(_app(_gate(loader: _settings(() => active))));
    await tester.pump();
    expect(find.text(_title), findsOneWidget);

    active = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    expect(find.text(_title), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la consulta se repite cada intervalo y activa el mantenimiento', (
    tester,
  ) async {
    var active = false;
    var calls = 0;
    await tester.pumpWidget(
      _app(
        _gate(
          loader: ({bool forceRefresh = false}) async {
            calls++;
            return <String, dynamic>{'maintenance_mode': active};
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_title), findsNothing);
    final before = calls;

    active = true;
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(calls, greaterThan(before));
    expect(find.text(_title), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en Preview no se consulta ni se bloquea, aunque el mantenimiento esté encendido', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        _gate(
          preview: ValueNotifier<bool>(true),
          loader: ({bool forceRefresh = false}) async {
            calls++;
            return <String, dynamic>{'maintenance_mode': true};
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(minutes: 3));
    expect(calls, 0);
    expect(find.text(_title), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin sesión no se muestra la pantalla: se puede llegar al inicio de sesión', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        _gate(
          resolved: ValueNotifier<bool>(false),
          loader: ({bool forceRefresh = false}) async {
            calls++;
            return <String, dynamic>{'maintenance_mode': true};
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(minutes: 3));
    expect(calls, 0);
    expect(find.text(_title), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('al iniciar sesión se reconoce el entorno: Producción se bloquea', (
    tester,
  ) async {
    final preview = ValueNotifier<bool>(false);
    final resolved = ValueNotifier<bool>(false);
    var calls = 0;
    await tester.pumpWidget(
      _app(
        _gate(
          preview: preview,
          resolved: resolved,
          loader: ({bool forceRefresh = false}) async {
            calls++;
            return <String, dynamic>{'maintenance_mode': true};
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_title), findsNothing);

    // Inicia sesión una cuenta de Producción (mismo orden que la app).
    preview.value = false;
    resolved.value = true;
    await tester.pump();
    await tester.pump();
    expect(calls, 1);
    expect(find.text(_title), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('al iniciar sesión se reconoce el entorno: Preview pasa sin bloquear', (
    tester,
  ) async {
    final preview = ValueNotifier<bool>(false);
    final resolved = ValueNotifier<bool>(false);
    var calls = 0;
    await tester.pumpWidget(
      _app(
        _gate(
          preview: preview,
          resolved: resolved,
          loader: ({bool forceRefresh = false}) async {
            calls++;
            return <String, dynamic>{'maintenance_mode': true};
          },
        ),
      ),
    );
    await tester.pump();

    // Inicia sesión una cuenta de Preview (mismo orden que la app).
    preview.value = true;
    resolved.value = true;
    await tester.pump();
    await tester.pump();
    expect(calls, 0);
    expect(find.text(_title), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el icono de arriba cierra la sesión y deja volver a iniciar', (
    tester,
  ) async {
    final resolved = ValueNotifier<bool>(true);
    var signedOut = 0;
    await tester.pumpWidget(
      _app(
        _gate(
          resolved: resolved,
          loader: _settings(() => true),
          onSignOut: () async {
            signedOut++;
            resolved.value = false; // la app reinicia el entorno al cerrar sesión
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_title), findsOneWidget);
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pump();
    await tester.pump();
    expect(signedOut, 1);
    // Sin sesión se ve el inicio de sesión, no la pantalla de mantenimiento.
    expect(find.text(_title), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('encender o apagar el mantenimiento no reinicia la app', (
    tester,
  ) async {
    var active = false;
    var starts = 0;
    await tester.pumpWidget(
      _app(
        _gate(
          loader: _settings(() => active),
          child: _Probe(onStart: () => starts++),
        ),
      ),
    );
    await tester.pump();
    expect(starts, 1);

    active = true;
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(find.text(_title), findsOneWidget);

    active = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    expect(find.text(_title), findsNothing);
    expect(starts, 1, reason: 'la app debe conservar su estado');
    await tester.pumpWidget(const SizedBox());
  });

  test('la app monta la puerta por fuera de la de actualización y con cierre de sesión', () {
    final main = File('lib/mobile_main.dart').readAsStringSync();
    final gate = main.indexOf('return MaintenanceGate(');
    final update = main.indexOf('AndroidReleaseUpdateGate(child: child');
    expect(gate, greaterThan(0));
    expect(update, greaterThan(gate));
    expect(main, contains('onSignOut: _logout,'));
    expect(main, contains("import 'maintenance_gate.dart';"));
  });

  test('el entorno se marca como resuelto al iniciar sesión y se limpia al cerrarla', () {
    final channel = File('lib/core/runtime_channel.dart').readAsStringSync();
    expect(channel, contains('resolvedListenable.value = true;'));
    expect(channel, contains('resolvedListenable.value = false;'));
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onStart});
  final VoidCallback onStart;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) => const Text('APP');
}

import 'dart:async';

import 'package:expressdelivery/express_timed_future_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _textBuilder(BuildContext context, AsyncSnapshot<String> snapshot) {
  if (snapshot.hasData) return Text(snapshot.data!);
  return const Center(child: CircularProgressIndicator());
}

void main() {
  testWidgets('una carga que se cuelga termina con mensaje y Reintentar',
      (tester) async {
    final never = Completer<String>();
    await tester.pumpWidget(_host(
      ExpressTimedFutureBuilder<String>(
        load: () => never.future,
        timeout: const Duration(milliseconds: 50),
        builder: _textBuilder,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('La conexión está tardando demasiado.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Reintentar vuelve a intentar y muestra el resultado',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(
      ExpressTimedFutureBuilder<String>(
        load: () {
          calls++;
          // La primera carga se cuelga; la del reintento responde.
          return calls == 1
              ? Completer<String>().future
              : Future<String>.value('listo');
        },
        timeout: const Duration(milliseconds: 50),
        builder: _textBuilder,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('listo'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('no se duplican cargas mientras una está en curso',
      (tester) async {
    var calls = 0;
    final retry = Completer<String>();
    await tester.pumpWidget(_host(
      ExpressTimedFutureBuilder<String>(
        load: () {
          calls++;
          return calls == 1 ? Completer<String>().future : retry.future;
        },
        timeout: const Duration(milliseconds: 200),
        builder: _textBuilder,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    await tester.tap(find.text('Reintentar'));
    // Mientras el reintento está en curso, varios frames no lanzan más cargas.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(calls, 2);

    retry.complete('ok');
    await tester.pumpAndSettle();
    expect(find.text('ok'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('un refresco conserva lo mostrado y marca Actualizando…',
      (tester) async {
    late StateSetter setOuter;
    var source = Future<String>.value('A');
    await tester.pumpWidget(_host(
      StatefulBuilder(builder: (context, setState) {
        setOuter = setState;
        return ExpressTimedFutureBuilder<String>(
          load: () => source,
          future: source,
          builder: _textBuilder,
        );
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);

    final refresh = Completer<String>();
    setOuter(() {
      source = refresh.future;
    });
    await tester.pump();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('Actualizando…'), findsOneWidget);

    refresh.complete('B');
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(find.text('Actualizando…'), findsNothing);
  });

  testWidgets('otra entidad no reutiliza datos de la anterior', (tester) async {
    late StateSetter setOuter;
    var entity = 1;
    var source = Future<String>.value('viaje-1');
    await tester.pumpWidget(_host(
      StatefulBuilder(builder: (context, setState) {
        setOuter = setState;
        return ExpressTimedFutureBuilder<String>(
          entityKey: entity,
          load: () => source,
          future: source,
          builder: _textBuilder,
        );
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('viaje-1'), findsOneWidget);

    final next = Completer<String>();
    setOuter(() {
      entity = 2;
      source = next.future;
    });
    await tester.pump();
    expect(find.text('viaje-1'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    next.complete('viaje-2');
    await tester.pumpAndSettle();
    expect(find.text('viaje-2'), findsOneWidget);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:expressdelivery/express_publish_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<BuildContext> pumpHome(WidgetTester tester) async {
    // La fuente de prueba es más ancha que la real: superficie más alta.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold(body: Text('mapa'));
          },
        ),
      ),
    );
    return context;
  }

  testWidgets('loader covers the screen only while the publish call runs',
      (tester) async {
    final context = await pumpHome(tester);
    final completer = Completer<String>();

    final future = runExpressPublishing<String>(context, () => completer.future);
    await tester.pump();

    expect(find.text('Buscando conductores…'), findsOneWidget);
    expect(find.text('Estamos publicando tu solicitud.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete('solicitud-1');
    expect(await future, 'solicitud-1');
    await tester.pump();

    expect(find.text('Buscando conductores…'), findsNothing);
  });

  testWidgets('loader is removed and the error is rethrown on failure',
      (tester) async {
    final context = await pumpHome(tester);

    final future = runExpressPublishing<String>(
      context,
      () async => throw StateError('publicación rechazada'),
    );
    await expectLater(future, throwsStateError);
    await tester.pump();

    expect(find.text('Buscando conductores…'), findsNothing);
    expect(find.text('mapa'), findsOneWidget);
  });

  testWidgets('loader absorbs taps with a non-dismissible barrier',
      (tester) async {
    // La fuente de prueba es mucho más ancha que la real: superficie más alta.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(home: ExpressPublishLoader()),
    );

    // El velo absorbe toques sin depender de una ruta: no se puede descartar.
    expect(find.byType(AbsorbPointer), findsWidgets);
    final absorb = tester.widget<AbsorbPointer>(find.descendant(
      of: find.byType(ExpressPublishLoader),
      matching: find.byType(AbsorbPointer),
    ).first);
    expect(absorb.absorbing, isTrue);
  });

  testWidgets('large system font does not break the publish text into fragments',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const ExpressPublishLoader(),
      ),
    );

    // Con escala 2.0 del sistema, el cargador limita el escalado a 1.3.
    // (La fuente de prueba es Ahem, así que se mide la escala efectiva, no el alto.)
    final rich = tester.widget<RichText>(find.descendant(
      of: find.byType(ExpressPublishLoader),
      matching: find.byType(RichText),
    ).first);
    expect(rich.textScaler.scale(18), lessThanOrEqualTo(18 * 1.3 + 0.01));
    expect(tester.takeException(), isNull);
  });

  test('the publish screen uses the loader and hides the submitting card', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();

    expect(home, contains('runExpressPublishing<Map<String, dynamic>>('));
    expect(home, isNot(contains("processingTitle: 'Buscando conductores…'")));
    final start = home.indexOf('    if (submittingRide) {\n      return const SizedBox.shrink();');
    expect(start, isNonNegative);
    expect(
      home.substring(start, start + 200),
      isNot(contains('Ofreciendo tu tarifa')),
    );
  });
}

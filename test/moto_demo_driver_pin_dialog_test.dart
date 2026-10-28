import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/video_style_home.dart';

void main() {
  testWidgets('driver asks for PIN and blocks incorrect demo codes', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          result = await showExpressMotoDemoPinDialog(context);
        },
        child: const Text('Abrir PIN'),
      )),
    )));

    await tester.tap(find.text('Abrir PIN'));
    await tester.pumpAndSettle();
    expect(find.text('PIN de abordaje'), findsOneWidget);
    expect(find.text('Pide al pasajero su PIN de 4 dígitos.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Iniciar viaje'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('PIN incorrecto'), findsOneWidget);
    expect(find.text('PIN de abordaje'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4826');
    await tester.tap(find.text('Iniciar viaje'));
    await tester.pumpAndSettle();
    expect(result, '4826');
    expect(find.text('PIN de abordaje'), findsNothing);
  });

  testWidgets('cancelling PIN does not start a trip', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          result = await showExpressMotoDemoPinDialog(context);
        },
        child: const Text('Abrir PIN'),
      )),
    )));
    await tester.tap(find.text('Abrir PIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('PIN de abordaje'), findsNothing);
  });
}

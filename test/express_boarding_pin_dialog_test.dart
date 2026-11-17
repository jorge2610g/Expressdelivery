import 'package:expressdelivery/express_boarding_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(void Function(String?) onResult) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            onResult(await showExpressBoardingPinDialog(context));
          },
          child: const Text('Abrir PIN'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('PIN incompleto muestra error y no cierra el diálogo',
      (tester) async {
    String? result = 'sin respuesta';
    await tester.pumpWidget(_host((value) => result = value));

    await tester.tap(find.text('Abrir PIN'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Iniciar viaje'));
    await tester.pumpAndSettle();

    expect(find.text('El PIN debe tener 4 dígitos.'), findsOneWidget);
    expect(find.text('PIN de abordaje'), findsOneWidget);
    expect(result, 'sin respuesta');
  });

  testWidgets('signo en el PIN no pasa como dígitos válidos', (tester) async {
    String? result = 'sin respuesta';
    await tester.pumpWidget(_host((value) => result = value));

    await tester.tap(find.text('Abrir PIN'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '+123');
    await tester.tap(find.text('Iniciar viaje'));
    await tester.pumpAndSettle();

    expect(find.text('El PIN debe tener 4 dígitos.'), findsOneWidget);
    expect(result, 'sin respuesta');
  });

  testWidgets('PIN válido se devuelve y el diálogo se cierra', (tester) async {
    String? result;
    await tester.pumpWidget(_host((value) => result = value));

    await tester.tap(find.text('Abrir PIN'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '4826');
    await tester.tap(find.text('Iniciar viaje'));
    await tester.pumpAndSettle();

    expect(result, '4826');
    expect(find.text('PIN de abordaje'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelar devuelve null sin iniciar viaje', (tester) async {
    String? result = 'sin respuesta';
    await tester.pumpWidget(_host((value) => result = value));

    await tester.tap(find.text('Abrir PIN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('PIN de abordaje'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

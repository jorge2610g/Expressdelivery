import 'package:expressdelivery/cancellation_debt_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pasajero ve monto y puede ir a Pagos y billetera', (
    tester,
  ) async {
    bool? decision;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                decision = await showCancellationDebtBlock(
                  context,
                  Exception(
                    'Tienes una deuda por cancelación de 500 CLP. code: P0001',
                  ),
                  driver: false,
                );
              },
              child: const Text('Probar aviso'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Probar aviso'));
    await tester.pumpAndSettle();

    expect(find.text('Deuda por cancelación'), findsOneWidget);
    expect(find.text('Monto pendiente'), findsOneWidget);
    expect(find.text('CLP 500'), findsOneWidget);
    expect(
      find.text('Para solicitar otro viaje, primero debes saldar esta deuda.'),
      findsOneWidget,
    );
    expect(find.textContaining('P0001'), findsNothing);

    await tester.tap(find.text('Ir a Pagos y billetera'));
    await tester.pumpAndSettle();
    expect(decision, isTrue);
  });

  testWidgets('conductor ve su descripción y puede cerrar el aviso', (
    tester,
  ) async {
    bool? decision;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                decision = await showCancellationDebtBlock(
                  context,
                  Exception(
                    'Tienes una deuda pendiente por cancelación de CLP 500. '
                    'PostgrestException(code: P0001)',
                  ),
                  driver: true,
                );
              },
              child: const Text('Probar aviso'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Probar aviso'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Para conectarte y aceptar viajes, primero debes saldar esta deuda.',
      ),
      findsOneWidget,
    );
    expect(find.text('CLP 500'), findsOneWidget);
    expect(find.textContaining('P0001'), findsNothing);

    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(decision, isFalse);
  });
}

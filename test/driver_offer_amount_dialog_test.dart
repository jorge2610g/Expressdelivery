import 'package:expressdelivery/driver_offer_amount_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<DriverOfferInput?> openDialog(
    WidgetTester tester, {
    required List<Object> errors,
    required void Function(DriverOfferInput?) onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialog<DriverOfferInput>(
                  context: context,
                  builder: (_) => const DriverOfferDialog(
                    title: 'Enviar oferta',
                    fareLabel: 'Tu tarifa',
                    initialFare: '1500',
                  ),
                );
                onResult(result);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return null;
  }

  testWidgets('returns the typed fare and arrival time when confirmed',
      (tester) async {
    final errors = <Object>[];
    DriverOfferInput? result;
    await openDialog(
      tester,
      errors: errors,
      onResult: (value) => result = value,
    );

    expect(find.text('Enviar oferta'), findsOneWidget);
    expect(find.text('1500'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '1750');
    await tester.enterText(find.byType(TextField).at(1), '8');
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.fareText, '1750');
    expect(result!.etaText, '8');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling returns null and closes without errors',
      (tester) async {
    DriverOfferInput? result = const DriverOfferInput(
      fareText: 'x',
      etaText: 'y',
    );
    await openDialog(
      tester,
      errors: <Object>[],
      onResult: (value) => result = value,
    );

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('Enviar oferta'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

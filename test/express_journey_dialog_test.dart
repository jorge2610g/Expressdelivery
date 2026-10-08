import 'package:expressdelivery/express_journey_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(320, 560), const Size(412, 915)]) {
    testWidgets('responsive Express decision fits ${size.width}x${size.height}',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExpressJourneyDialog(
              icon: Icons.radar_rounded,
              title: '¿Seguimos buscando?',
              subtitle: 'Puedes buscar otro conductor o mejorar tu oferta '
                  'sin abandonar la solicitud.',
              content: const Text('Oferta actual: \$ 1.641'),
              actions: [
                FilledButton(
                  onPressed: () {},
                  child: const Text('Seguir buscando 3 min'),
                ),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Subir mi oferta'),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('Cancelar búsqueda'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('¿Seguimos buscando?'), findsOneWidget);
      expect(find.text('Oferta actual: \$ 1.641'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('respects large text scale without a RenderFlex overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 560),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: ExpressJourneyDialog(
              icon: Icons.payments_rounded,
              title: 'Confirmar cobro del viaje',
              subtitle: 'Antes de terminar verifica el efectivo recibido.',
              content: const Text('\$ 1.500'),
              actions: [
                FilledButton(
                  onPressed: () {},
                  child: const Text('Ya cobré · Finalizar'),
                ),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Volver al viaje'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirmar cobro del viaje'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

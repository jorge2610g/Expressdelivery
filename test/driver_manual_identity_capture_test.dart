import 'package:expressdelivery/driver_manual_identity_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guided Bolivia intake captures both sides and face, pending review',
      (tester) async {
    DriverManualIdentityCaptureResult? result;
    final slots = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => FilledButton(
          onPressed: () async {
            result = await Navigator.push<DriverManualIdentityCaptureResult>(
              context,
              MaterialPageRoute(
                builder: (_) => DriverManualIdentityCapturePage(
                  uploadCameraPhoto: (slot) async {
                    slots.add(slot);
                    return 'fake-user-id/documents/fake-requirement/$slot.jpg';
                  },
                ),
              ),
            );
          },
          child: const Text('Iniciar verificación manual'),
        )),
      ),
    ));

    await tester.tap(find.text('Iniciar verificación manual'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Frente de tu carné'), findsOneWidget);
    for (final slot in <String>['front','back','selfie']) {
      await tester.ensureVisible(find.text('Abrir cámara').first);
      await tester.tap(find.text('Abrir cámara').first);
      await tester.pumpAndSettle();
      expect(slots.last, slot);
    }
    expect(find.text('Revisa tus documentos'), findsOneWidget);
    expect(find.textContaining('todavía NO han sido verificadas'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), 'CI12345');
    await tester.ensureVisible(
        find.text('Guardar documentos para revisión'));
    await tester.tap(find.text('Guardar documentos para revisión'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.documentNumber, 'CI12345');
    expect(result!.frontPath, contains('front.jpg'));
    expect(result!.backPath, contains('back.jpg'));
    expect(result!.selfiePath, contains('selfie.jpg'));
  });
}

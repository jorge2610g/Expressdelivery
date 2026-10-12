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
    expect(find.textContaining('Carga el frente de tu carné'), findsOneWidget);
    for (final slot in <String>['front','back','selfie']) {
      await tester.ensureVisible(find.text('Abrir cámara').first);
      await tester.tap(find.text('Abrir cámara').first);
      await tester.pumpAndSettle();
      expect(slots.last, slot);
    }
    expect(find.text('Revisa tus documentos'), findsOneWidget);
    expect(find.textContaining('Un administrador revisará tu información'),
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

  testWidgets('previously saved photos may be kept without reopening camera',
      (tester) async {
    DriverManualIdentityCaptureResult? result;
    var uploads = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => FilledButton(
          onPressed: () async {
            result = await Navigator.push<DriverManualIdentityCaptureResult>(
              context,
              MaterialPageRoute(builder: (_) => DriverManualIdentityCapturePage(
                initialDocumentNumber: 'CI12345',
                initialFrontPath: 'fake/documents/id/front.jpg',
                initialBackPath: 'fake/documents/id/back.jpg',
                initialSelfiePath: 'fake/documents/id/selfie.jpg',
                uploadCameraPhoto: (slot) async {
                  uploads++;
                  return null;
                },
              )),
            );
          },
          child: const Text('Revisar ya cargado'),
        )),
      ),
    ));

    await tester.tap(find.text('Revisar ya cargado'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(find.text('Documento cargado'), findsOneWidget);
      await tester.ensureVisible(find.text('Continuar'));
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Revisa tus documentos'), findsOneWidget);
    await tester.ensureVisible(find.text('Guardar documentos para revisión'));
    await tester.tap(find.text('Guardar documentos para revisión'));
    await tester.pumpAndSettle();

    expect(uploads, 0);
    expect(result?.documentNumber, 'CI12345');
    expect(result?.frontPath, 'fake/documents/id/front.jpg');
    expect(result?.backPath, 'fake/documents/id/back.jpg');
    expect(result?.selfiePath, 'fake/documents/id/selfie.jpg');
  });
}

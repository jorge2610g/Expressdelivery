import 'package:expressdelivery/video_style_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PIN del pasajero visible en el teléfono del conductor',
      (tester) async {
    var started = false;
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SingleChildScrollView(
        child: ExpressMotoDemoInlinePin(
          onVerified: () => started = true,
          onCancel: () => cancelled = true,
        ),
      ))),
    ));

    expect(find.text('PIN de abordaje'), findsOneWidget);
    expect(find.text('PIN del pasajero'), findsOneWidget);
    expect(find.byKey(const Key('express-moto-demo-pin-input')), findsOneWidget);
    expect(find.text('Iniciar viaje'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('express-moto-demo-pin-input')), '1234');
    await tester.tap(find.byKey(const Key('express-moto-demo-start-with-pin')));
    await tester.pump();
    expect(started, isFalse);
    expect(find.textContaining('PIN incorrecto'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('express-moto-demo-pin-input')), '4826');
    await tester.tap(find.byKey(const Key('express-moto-demo-start-with-pin')));
    await tester.pump();
    expect(started, isTrue);
    expect(cancelled, isFalse);
  });

  testWidgets('returning from the boarding step never starts a trip',
      (tester) async {
    var started = false;
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SingleChildScrollView(
        child: ExpressMotoDemoInlinePin(
          onVerified: () => started = true,
          onCancel: () => cancelled = true,
        ),
      ))),
    ));
    await tester.tap(find.text('Volver a la recogida'));
    expect(started, isFalse);
    expect(cancelled, isTrue);
  });
}

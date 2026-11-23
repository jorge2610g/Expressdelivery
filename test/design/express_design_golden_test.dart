import 'dart:io';
import 'dart:typed_data';

import 'package:expressdelivery/design/express_passenger_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carga fuentes reales (en pruebas Flutter usa letra de bloques por defecto).
Future<void> _loadFonts() async {
  const root = '/root/flutter-sdk/flutter/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String name) async {
    final bytes = await File('$root/$name').readAsBytes();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(read('Roboto-Regular.ttf'))
    ..addFont(read('Roboto-Medium.ttf'))
    ..addFont(read('Roboto-Bold.ttf'))
    ..addFont(read('Roboto-Black.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _shot(WidgetTester tester, Widget screen, String name) async {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(body: Center(child: screen)),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('2 · elige tu viaje', (tester) async {
    await _shot(tester, const ExpressChooseTripScreen(), 'p2_elegir');
  });
  testWidgets('2b · elige tu viaje (oferta elegida)', (tester) async {
    await _shot(tester, const ExpressChooseTripScreen(fixedSelected: false),
        'p2b_elegir_oferta');
  });
  testWidgets('3 · buscando conductor', (tester) async {
    await _shot(tester, const ExpressSearchingScreen(), 'p3_buscando');
  });
  testWidgets('4 · seguimos buscando', (tester) async {
    await _shot(tester, const ExpressKeepSearchingScreen(), 'p4_decision');
  });
}

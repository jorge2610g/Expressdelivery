import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un Material con color absorbe los toques de toda la pantalla; con
/// MaterialType.transparency deja pasar los toques a lo que hay debajo (el mapa
/// del conductor mientras llega una oferta).
void main() {
  Future<int> tapsReaching(WidgetTester tester, Widget overlay) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: GestureDetector(onTap: () => taps++, child: const ColoredBox(color: Colors.white)),
          ),
          Positioned.fill(child: overlay),
        ]),
      ),
    ));
    await tester.tapAt(const Offset(200, 300));
    return taps;
  }

  testWidgets('Material con color bloquea el mapa', (tester) async {
    final taps = await tapsReaching(
      tester,
      Material(color: Colors.transparent, child: SafeArea(child: Stack(children: const []))),
    );
    expect(taps, 0);
  });

  testWidgets('Material transparency deja pasar los toques al mapa', (tester) async {
    final taps = await tapsReaching(
      tester,
      Material(type: MaterialType.transparency, child: SafeArea(child: Stack(children: const []))),
    );
    expect(taps, 1);
  });
}

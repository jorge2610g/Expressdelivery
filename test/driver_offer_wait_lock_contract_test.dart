import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato del cuadro "Esperando confirmación del pasajero": centrado y con
/// capa transparente que absorbe toques. El comportamiento en pantalla se
/// valida en emulador/teléfono.
void main() {
  late String home;

  setUpAll(() {
    home = File('lib/video_style_home.dart').readAsStringSync();
  });

  String waitingOverlayBuild() {
    final start = home.indexOf('class _DriverOfferWaitingOverlay');
    expect(start, isNonNegative);
    final end = home.indexOf('\n}\n', start);
    return home.substring(start, end);
  }

  test('waiting card blocks every touch behind it', () {
    final build = waitingOverlayBuild();

    expect(build, contains('return Stack('));
    expect(
      build,
      contains('ModalBarrier(dismissible: false, color: Colors.transparent)'),
    );
    expect(build, isNot(contains('IgnorePointer(')));
  });

  test('waiting card is centered, not pinned to the bottom', () {
    final build = waitingOverlayBuild();

    expect(build, contains('child: Center('));
    expect(build, isNot(contains('Alignment.bottomCenter')));
  });
}

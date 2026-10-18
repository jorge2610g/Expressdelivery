import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Traducciones nativas de la notificación de llamada (ZEGO) al español.
void main() {
  test('overlay ships Spanish strings for the ZEGO call notification buttons', () {
    final values = File('android_overlay/res/values-es/strings.xml').readAsStringSync();
    expect(values, contains('<string name="text_accept">Aceptar</string>'));
    expect(values, contains('<string name="text_decline">Rechazar</string>'));
    expect(values, contains('<string name="text_missed_call">Llamada perdida</string>'));
    expect(values, contains('<string name="text_call_back">Devolver llamada</string>'));
  });

  test('the apply script copies the Spanish resources into the Android project', () {
    final script = File('.github/scripts/apply_floating_overlay.py').readAsStringSync();
    expect(script, contains("overlay / 'res' / 'values-es' / 'strings.xml'"));
    expect(script, contains("res_dir / 'values-es'"));
  });
}

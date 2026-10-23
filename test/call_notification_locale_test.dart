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

  test('every Spanish call label has a default value, so release lint finds no ExtraTranslation', () {
    // Equivalente estático de la comprobación de lint: cada clave en values-es debe existir
    // también en el idioma por defecto. Sin ella, lintVitalRelease falla la compilación.
    final spanish = File('android_overlay/res/values-es/strings.xml').readAsStringSync();
    final base = File('android_overlay/res/values/express_call_labels.xml').readAsStringSync();
    final nameOf = RegExp(r'<string name="([^"]+)"');
    final spanishKeys = nameOf.allMatches(spanish).map((m) => m.group(1)!).toSet();
    final baseKeys = nameOf.allMatches(base).map((m) => m.group(1)!).toSet();
    expect(spanishKeys, isNotEmpty);
    expect(spanishKeys.difference(baseKeys), isEmpty);
  });

  test('the apply script ships the default values file without overwriting the scaffold strings', () {
    final script = File('.github/scripts/apply_floating_overlay.py').readAsStringSync();
    expect(script, contains("overlay / 'res' / 'values' / 'express_call_labels.xml'"));
    expect(script, contains("res_dir / 'values'"));
    expect(script, isNot(contains("res_dir / 'values' / 'strings.xml'")));
  });
}

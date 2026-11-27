import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el aviso de notificaciones bloqueadas es amable y limitado', () {
    final src = File('lib/push_permission_prompt.dart').readAsStringSync();
    expect(src, contains('Activa las notificaciones'));
    expect(src, contains('Abrir ajustes'));
    expect(src, contains('_snoozeDays = 3'));
    expect(src, contains('_refreshHours = 6'));
    // Nunca en la web ni a conductores (tienen su propia pantalla de permisos).
    expect(src, contains('!kIsWeb'));
    final host = File('lib/connected_experience.dart').readAsStringSync();
    expect(host, contains("PushPermissionPrompt(\n        enabled: mode != 'driver'"));
  });
}

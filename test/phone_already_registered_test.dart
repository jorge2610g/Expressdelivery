import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/services/express_service.dart';

void main() {
  test('el aviso de teléfono repetido es claro', () {
    expect(PhoneAlreadyRegisteredException.message,
        contains('ya está registrado en otra cuenta'));
    expect(const PhoneAlreadyRegisteredException().toString(),
        PhoneAlreadyRegisteredException.message);
  });

  test('el registro y las pantallas de perfil comprueban el teléfono', () {
    final auth = File('lib/auth_entry.dart').readAsStringSync();
    expect(auth, contains('phone_is_registered_v1'));
    final svc = File('lib/services/express_service.dart').readAsStringSync();
    expect(svc, contains('PhoneAlreadyRegisteredException()'));
    for (final f in ['lib/express_account_pages.dart', 'lib/connected_experience.dart']) {
      expect(File(f).readAsStringSync(), contains('on PhoneAlreadyRegisteredException'));
    }
  });
}

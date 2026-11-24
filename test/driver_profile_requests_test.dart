import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = File('lib/services/express_service.dart').readAsStringSync();
  final profile = File('lib/express_account_pages.dart').readAsStringSync();

  test('el conductor aprobado envía solicitud en vez de editar su perfil', () {
    expect(service, contains('driver_request_profile_change_v1'));
    expect(service, contains('Future<bool> updateProfile('));
    expect(service, contains('_isApprovedDriver()'));
    expect(service, contains('/profile-change/'));
  });

  test('tocar la foto del conductor abre el cambio de foto con revisión', () {
    expect(profile, contains('onTap: _changePhoto'));
    expect(profile, contains('Foto enviada a revisión'));
    expect(profile, contains('_ProfileChangeRequestsCard('));
  });
}

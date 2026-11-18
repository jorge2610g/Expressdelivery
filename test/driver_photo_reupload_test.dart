import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Conductores con foto de perfil reemplazada deben volver a cargarla.
void main() {
  late String banner;
  late String account;
  late String migration;

  setUpAll(() {
    banner = File('lib/driver_photo_reupload_banner.dart').readAsStringSync();
    account = File('lib/connected_experience.dart').readAsStringSync();
    migration = File(
      'supabase/migrations/20261118110000_driver_profile_photo_reupload_flag.sql',
    ).readAsStringSync();
  });

  test('el aviso lee la marca con la RPC y abre el paso de foto de perfil', () {
    expect(banner, contains("'my_driver_profile_photo_reupload_required'"));
    expect(banner, contains("focusSection: 'profile'"));
    expect(banner, contains('editExisting: true'));
    expect(banner, contains('Tu foto de perfil fue rechazada'));
    expect(banner, contains('Al subirla podrás volver a ponerte en línea.'));
    expect(banner, contains('if (!_required) return const SizedBox.shrink();'));
  });

  test('el aviso aparece en Cuenta solo para conductores', () {
    expect(account, contains("import 'driver_photo_reupload_banner.dart';"));
    expect(account, contains('if (widget.driver)\n                DriverPhotoReuploadBanner(service: widget.service),'));
  });

  test('la base marca a los afectados y limpia la marca al subir una foto nueva', () {
    expect(migration, contains('add column if not exists profile_photo_reupload_required'));
    expect(migration, contains("where profile_photo_path like '%/documents/%'"));
    expect(migration, contains('driver_profile_photo_reupload_clear'));
    expect(migration, contains("new.profile_photo_path not like '%/documents/%'"));
    expect(migration, contains('revoke execute on function public.my_driver_profile_photo_reupload_required() from public, anon;'));
    expect(migration, isNot(contains('drop table')));
  });
}

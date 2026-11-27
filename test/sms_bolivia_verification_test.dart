import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la función phone-otp solo acepta Bolivia y respeta el interruptor', () {
    final src = File('supabase/functions/phone-otp/index.ts').readAsStringSync();
    expect(src, contains("dialCode = '+591'"));
    expect(src, contains('sms_verification_passenger_enabled'));
    expect(src, contains('sms_disabled'));
    expect(src, isNot(contains("'+56'")));
  });

  test('la migración deja la verificación apagada y solo para cuentas nuevas', () {
    final sql = File(
      'supabase/migrations/20261127120000_phone_sms_bolivia_signup_verification.sql',
    ).readAsStringSync();
    expect(sql, contains("like '+591%'"));
    expect(sql, contains('sms_verification_rollout_at'));
    expect(sql, isNot(contains('sms_verification_passenger_enabled = true')));
  });

  test('el arranque falla en abierto si no se puede consultar la verificación', () {
    final svc = File('lib/services/express_service.dart').readAsStringSync();
    expect(svc, contains("<String, dynamic>{'required': false}"));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bolivia Preview transfer orders become pending test QR orders', () {
    final migration = File(
      'supabase/migrations/20261025170714_preview_marketplace_qr_simulator.sql',
    ).readAsStringSync();

    expect(migration, contains("new.channel in ('production','preview')"));
    expect(migration, contains("new.payment_status:='qr_pending'"));
    expect(migration, contains("'preview_test_qr',true"));
    expect(migration, contains("v_order.channel not in ('production','preview')"));
  });

  test('Preview QR uses a simulator action and never calls VeriPagos', () {
    final function = File(
      'supabase/functions/marketplace-payments/index.ts',
    ).readAsStringSync();
    final previewStart = function.indexOf(
      '// Preview orders use a synthetic QR code',
    );
    final productionStart = function.indexOf(
      "\n      if (action === 'global_qr_create') {",
      previewStart,
    );
    expect(previewStart, greaterThanOrEqualTo(0));
    expect(productionStart, greaterThan(previewStart));

    final previewFlow = function.substring(previewStart, productionStart);
    expect(previewFlow, contains('preview_simulator'));
    expect(previewFlow, contains("action === 'global_qr_simulate'"));
    expect(previewFlow, contains("p_status:'paid'"));
    expect(previewFlow, isNot(contains('createVeripagosQr(')));
    expect(previewFlow, isNot(contains('verifyVeripagosQr(')));
  });

  test('Preview QR screen explains the test and offers simulated payment', () {
    final screen = File('lib/express_delivery_v2_page.dart').readAsStringSync();
    expect(screen, contains('Este QR solo sirve para la prueba'));
    expect(screen, contains("_action(_previewTest ? 'simulate' : 'verify')"));
    expect(screen, contains("'Pago de prueba confirmado. No se hizo ningún cobro.'"));
  });
}

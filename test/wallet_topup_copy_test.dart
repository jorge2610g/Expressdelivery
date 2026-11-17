import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wallet top-up dialog uses one short, customer-facing description', () {
    final source = File('lib/express_account_pages.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _requestTopup()');
    final end = source.indexOf('        actions: [', start + 1);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final dialog = source.substring(start, end);

    expect(
      dialog,
      contains('Ingresa el monto que deseas agregar a tu billetera.'),
    );
    expect(dialog, isNot(contains('Preview')));
    expect(dialog, isNot(contains('VeriPagos')));
    expect(dialog, isNot(contains('Mercado Pago')));
  });
}

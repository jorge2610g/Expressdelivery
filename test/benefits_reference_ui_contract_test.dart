import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = File('lib/benefits_page.dart').readAsStringSync();

  test('passenger and driver get selectable benefit modules', () {
    expect(page, contains("('coupon', 'Cupones')"));
    expect(page, contains("('activation', 'Reglas')"));
    expect(page, contains("('loyalty', 'Fidelidad')"));
    expect(page, contains("('referral', 'Referidos')"));
    expect(page, contains("('driver_challenge', 'Retos')"));
    expect(page, contains("('wallet', 'Billetera')"));
    expect(page, contains('ChoiceChip('));
    expect(page, contains('GridView.count('));
  });

  test('driver referral page describes only plan-payment wallet rewards', () {
    expect(page, contains('cada pago de plan confirmado en Bolivia'));
    expect(page, contains('billetera interna'));
    expect(page, isNot(contains('COMISIÓN RECURRENTE')));
    expect(page, contains("item['type'] == _selectedModule"));
  });
}

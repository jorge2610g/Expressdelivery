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

  test('driver referral page describes the configured reward basis', () {
    expect(page, contains('Recibe la recompensa configurada cuando tu referido complete ${referral['min_paid_trips'] ?? 1} viajes pagados.'));
    expect(page, contains('Recibe ${referral['percent'] ?? 0}% de la comisión de Express por cada viaje pagado de tu referido.'));
    expect(page, contains('Recibe la comisión configurada cuando tu referido pague un plan.'));
    expect(page, contains('Tu código:'));
    expect(page, contains('Código del conductor que te invitó'));
    expect(page, isNot(contains('COMISIÓN RECURRENTE')));
    expect(page, contains("item['type'] == _selectedModule"));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_level_page.dart';

void main() {
  test('nombres de nivel', () {
    expect(driverLevelLabel('elite'), 'Élite');
    expect(driverLevelLabel('pro'), 'Pro');
    expect(driverLevelLabel('inicio'), 'Inicio');
    expect(driverLevelLabel(null), 'Inicio');
  });

  test('texto de cada criterio', () {
    expect(
      driverLevelCriterionText({'value': 12, 'target': 30, 'unit': 'viajes', 'higher_is_better': true}),
      '12 de 30 viajes',
    );
    expect(
      driverLevelCriterionText({'value': 20.8, 'target': 30, 'unit': '%', 'higher_is_better': true}),
      '20.8 de 30 %',
    );
    expect(
      driverLevelCriterionText({'value': 20, 'target': 15, 'unit': '%', 'higher_is_better': false}),
      '20 % (máximo 15 %)',
    );
  });

  test('avance hacia el objetivo', () {
    expect(driverLevelCriterionProgress({'met': true}), 1);
    expect(driverLevelCriterionProgress({'met': false, 'value': 6, 'target': 12, 'higher_is_better': true}), 0.5);
    expect(driverLevelCriterionProgress({'met': false, 'value': null, 'target': 12, 'higher_is_better': true}), 0);
  });
}

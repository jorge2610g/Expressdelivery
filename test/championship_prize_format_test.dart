import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/championship_prize_format.dart';

void main() {
  group('Campeonato Express prizes', () {
    test('formats legacy Chilean numbers in CLP', () {
      expect(championshipPrizeLabel('150000', 'CLP'), 'CLP 150.000');
      expect(championshipPrizeLabel('90.000', 'CLP'), 'CLP 90.000');
      expect(championshipPrizeLabel('50000', 'CLP'), 'CLP 50.000');
      expect(championshipPrizeLabel('CLP 150000', 'CLP'), 'CLP 150.000');
      expect(championshipPrizeLabel(r'$750', 'CLP'), 'CLP 750');
    });

    test('formats Bolivian amounts in BOB', () {
      expect(championshipPrizeLabel('500', 'BOB'), 'Bs 500');
      expect(championshipPrizeLabel('Bs 300', 'BOB'), 'Bs 300');
      expect(championshipPrizeLabel('250.50', 'BOB'), 'Bs 250.50');
    });

    test('keeps textual/non-cash prizes intact', () {
      expect(championshipPrizeLabel(
        'Premio de prueba: Bs 500 (no canjeable)', 'BOB'),
        'Premio de prueba: Bs 500 (no canjeable)');
      expect(championshipPrizeLabel(
        'Bs 500 + bono especial', 'BOB'), 'Bs 500 + bono especial');
      expect(championshipPrizeLabel(null, 'CLP'), 'Premio por anunciar');
    });
  });
}

import 'package:expressdelivery/passenger_search_fare_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CLP steps are whole pesos', () {
    expect(expressSearchFareStep('CLP'), 250);
    expect(expressSearchFareStep('clp '), 250);
  });

  test('BOB steps are one boliviano', () {
    expect(expressSearchFareStep('BOB'), 1);
  });

  test('unknown currency falls back to a conservative step', () {
    expect(expressSearchFareStep('XYZ'), 1);
    expect(expressSearchFareStep(''), 1);
  });
}

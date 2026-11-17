import 'package:expressdelivery/benefit_audience_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('muestra a quién va dirigido cada beneficio', () {
    expect(benefitAudienceLabel('drivers'), 'Conductores');
    expect(benefitAudienceLabel('passengers'), 'Pasajeros');
    expect(benefitAudienceLabel('all'), 'Todos los usuarios');
  });

  test('sin audiencia el beneficio va a todos', () {
    expect(benefitAudienceLabel(null), 'Todos los usuarios');
    expect(benefitAudienceLabel(''), 'Todos los usuarios');
  });
}

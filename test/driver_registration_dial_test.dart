import 'package:expressdelivery/driver_registration_web_portal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el código telefónico sale del país de la zona', () {
    expect(dialCodeForCountry('BO'), '+591');
    expect(dialCodeForCountry('bo'), '+591');
    expect(dialCodeForCountry(' CL '), '+56');
  });

  test('un país sin código soportado no cambia la selección', () {
    expect(dialCodeForCountry(null), isNull);
    expect(dialCodeForCountry(''), isNull);
    expect(dialCodeForCountry('AR'), isNull);
  });
}

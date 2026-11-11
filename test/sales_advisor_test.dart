import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/sales_advisor.dart';

void main() {
  test('lee el código del asesor del enlace del QR', () {
    expect(salesCodeFromUri(Uri.parse('https://expressviajes.online/r/ana-7k3')), 'ANA-7K3');
    expect(salesCodeFromUri(Uri.parse('https://expressviajes.online/?asesor=ANA-7K3')), 'ANA-7K3');
    expect(salesCodeFromUri(Uri.parse('https://expressviajes.online/')), isNull);
    expect(salesCodeFromUri(Uri.parse('https://expressviajes.online/r/a')), isNull);
    expect(salesCodeFromUri(Uri.parse('https://expressviajes.online/registro/conductor')), isNull);
  });

  test('reconoce el portal del asesor', () {
    expect(isSalesAdvisorPortalUri(Uri.parse('https://expressviajes.online/asesor')), isTrue);
    expect(isSalesAdvisorPortalUri(Uri.parse('https://expressviajes.online/?portal=asesor')), isTrue);
    expect(isSalesAdvisorPortalUri(Uri.parse('https://expressviajes.online/')), isFalse);
    expect(isSalesAdvisorPortalUri(Uri.parse('https://expressviajes.online/r/ANA-7K3')), isFalse);
  });

  test('rechaza códigos con formato inválido', () {
    expect(normalizeSalesCode(' ana-7k3 '), 'ANA-7K3');
    expect(normalizeSalesCode('a b'), isNull);
    expect(normalizeSalesCode(''), isNull);
    expect(normalizeSalesCode(null), isNull);
  });
}

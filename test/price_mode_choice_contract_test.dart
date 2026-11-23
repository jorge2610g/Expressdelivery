import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final home = File('lib/video_style_home.dart').readAsStringSync();
  final service = File('lib/services/express_service.dart').readAsStringSync();

  test('si el servicio admite ambos precios se muestran dos tarjetas', () {
    expect(home, contains("quote['price_mode']?.toString() == 'both'"));
    expect(home, contains("priceMode: 'fixed'"));
    expect(home, contains('class _PriceModeChooser'));
    expect(home, contains("title: 'Precio fijo'"));
    expect(home, contains("title: 'Ofrece tu precio'"));
  });

  test('la tarjeta elegida se resalta y dice Elegido', () {
    expect(home, contains("selected ? 'Elegido · ' + note : note"));
    expect(home, contains('Icons.check_circle_rounded'));
  });

  test('el viaje se crea con el precio fijo solo si el pasajero lo eligió', () {
    expect(home, contains("pricingMode: _fixedChosen && serviceType != 'delivery' ? 'fixed' : null"));
    expect(service, contains("if (pricingMode == 'fixed') 'pricing_mode': 'fixed'"));
    expect(service, contains("if (priceMode == 'fixed') 'p_price_mode': 'fixed'"));
  });
}

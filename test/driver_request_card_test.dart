import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/video_style_home.dart').readAsStringSync();

  test('la tarjeta de solicitud tiene cuenta atrás, caja de precio y tres datos', () {
    expect(src, contains('class _RequestCountdownRing'));
    expect(src, contains('class _RequestPriceBox'));
    for (final label in ["'VIAJE'", "'A RECOGER'", "'PAGO'"]) {
      expect(src, contains(label));
    }
  });

  test('precio fijo no negocia y ofertas piden más antes de contraofertar', () {
    expect(src, contains("'PRECIO FIJO'"));
    expect(src, contains("'OFRECE'"));
    expect(src, contains('PEDIR MÁS POR ESTE VIAJE'));
    expect(src, contains("'CONTRAOFERTAR · '"));
    expect(src, contains('showCounter: !fixedCoupon && !sequentialFixed'));
  });

  test('la solicitud programada no muestra una cuenta atrás de horas', () {
    expect(src, contains('_left > 3600'));
    expect(src, contains("'Abierta'"));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/video_style_home.dart').readAsStringSync();

  test('la ventana de una oferta dura 15 segundos, no 30', () {
    expect(src, contains('const int _driverOfferPopupSeconds = 15;'));
    expect(src, contains('Duration(seconds: _driverOfferPopupSeconds)'));
    expect(src, contains('driverDeliveryPopupRemaining = automatic ? _driverOfferPopupSeconds : 0;'));
    expect(src, contains('windowDeadline: driverRequestPopupExpiresAt'));
  });
}

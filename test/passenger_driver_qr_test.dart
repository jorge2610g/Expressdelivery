import 'package:expressdelivery/driver_payment_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el bloque de QR en curso aparece solo mientras el cobro está pedido',
      () {
    Map<String, dynamic> trip(String status, {Object? at}) => {
          'status': status,
          'payment_requested_at': at,
          'ride_requests': {'payment_method': 'driver_qr'},
        };
    const requested = '2026-11-02T01:00:00Z';

    expect(passengerShouldLoadDriverQr(trip('in_progress', at: requested)),
        isTrue);
    expect(passengerShouldLoadDriverQr(trip('in_progress')), isFalse);
    expect(passengerShouldLoadDriverQr(trip('completed', at: requested)),
        isFalse);
  });
}

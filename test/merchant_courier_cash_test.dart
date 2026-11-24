import 'package:expressdelivery/merchant_courier_cash.dart';
import 'package:expressdelivery/restaurant_courier_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entregar y cobrar: el cliente paga pedido + delivery y se calcula el vuelto', () {
    // Pedido 15.000 + delivery 2.500 = 17.500; el cliente paga con 20.000 → vuelto 2.500.
    final cash = MerchantCourierCash.fromRide({
      'merchant_courier': true,
      'merchant_service_type': 'collect',
      'merchant_order_amount': 15000,
      'merchant_change_for': 20000,
      'proposed_fare': 2500,
    })!;
    expect(cash.isCollect, isTrue);
    expect(cash.total, 17500);
    expect(cash.change, 2500);
  });

  test('entregar y cobrar sin billete: no hay vuelto', () {
    final cash = MerchantCourierCash.fromRide({
      'merchant_courier': true,
      'merchant_service_type': 'collect',
      'merchant_order_amount': '15000.00',
      'proposed_fare': '2500.00',
    })!;
    expect(cash.total, 17500);
    expect(cash.change, isNull);
  });

  test('pago justo: sin vuelto; monto insuficiente: sin vuelto', () {
    MerchantCourierCash c(double pays) => MerchantCourierCash.fromRide({
          'merchant_courier': true,
          'merchant_service_type': 'collect',
          'merchant_order_amount': 15000,
          'merchant_change_for': pays,
          'proposed_fare': 2500,
        })!;
    expect(c(17500).change, isNull);
    expect(c(16000).change, isNull);
  });

  test('solo entregar: no se cobra nada al cliente', () {
    final cash = MerchantCourierCash.fromRide({
      'merchant_courier': true,
      'merchant_service_type': 'deliver_only',
      'proposed_fare': 2500,
    })!;
    expect(cash.isCollect, isFalse);
    expect(cash.total, 0);
    expect(cash.fee, 2500);
    expect(cash.change, isNull);
  });

  test('un envío normal no es de restaurante', () {
    expect(MerchantCourierCash.fromRide({'merchant_courier': false, 'proposed_fare': 3000}), isNull);
    expect(MerchantCourierCash.fromRide({'proposed_fare': 3000}), isNull);
  });

  test('desglose del formulario del restaurante', () {
    final b = courierCollectBreakdown(order: 15000, fee: 2500, paysWith: 20000);
    expect(b.total, 17500);
    expect(b.change, 2500);
    expect(b.enough, isTrue);
    final short = courierCollectBreakdown(order: 15000, fee: 2500, paysWith: 15500);
    expect(short.enough, isFalse);
    expect(short.change, isNull);
    final none = courierCollectBreakdown(order: 15000, fee: 2500);
    expect(none.enough, isTrue);
    expect(none.change, isNull);
    expect(none.total, 17500);
  });
}

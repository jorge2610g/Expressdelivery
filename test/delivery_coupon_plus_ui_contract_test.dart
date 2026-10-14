import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Delivery customer profile has coupons and no merchant portal', () {
    final source = File('lib/express_delivery_v2_page.dart').readAsStringSync();
    final profile = source.substring(
      source.indexOf('class _DeliveryProfileTab'),
      source.indexOf('Future<void> _editBilling', source.indexOf('class _DeliveryProfileTab')),
    );
    expect(profile, contains("title: Text('Mis cupones')"));
    expect(profile, contains('DeliveryCustomerCouponsPage(service: service)'));
    expect(profile, contains("title: Text('Express Plus')"));
    expect(profile, isNot(contains("title: Text('Panel del comercio')")));
  });

  test('coupon wallet saves server-side, respects account channel, and checks redemptions', () {
    final sql = File('supabase/migrations/20261014051500_delivery_saved_coupons.sql')
        .readAsStringSync();
    final page = File('lib/delivery_customer_coupons_page.dart').readAsStringSync();
    final api = File('lib/services/express_service.dart').readAsStringSync();
    expect(sql, contains('auth.uid()'));
    expect(sql, contains('admin_user_runtime_environment(v_uid)'));
    expect(sql, contains("v_channel in ('preview','production')"));
    expect(sql, contains('marketplace_coupon_redemptions'));
    expect(sql, contains('create policy delivery_saved_coupons_select_own'));
    expect(sql, contains('on conflict (user_id,coupon_id,channel) do nothing'));
    expect(page, contains('Agregar nuevo cupón'));
    expect(page, contains('Copiar código'));
    expect(page, contains('¿Cómo uso un cupón?'));
    expect(api, contains("supabase.rpc('delivery_save_coupon'"));
    expect(api, contains("supabase.rpc('delivery_my_coupons'"));
  });

  test('Plus has reference-inspired benefits and real checkout, no mock cards', () {
    final plus = File('lib/marketplace_checkout_page.dart').readAsStringSync();
    expect(plus, contains('Más beneficios en cada pedido'));
    expect(plus, contains('Tus beneficios Plus'));
    expect(plus, contains('Elige tu plan'));
    expect(plus, contains('Total del plan'));
    expect(plus, contains('marketplaceCreatePlusPayment('));
    expect(plus, contains('marketplaceVerifyPlusPayment('));
    expect(plus, contains("selected['monthly_price']"));
    expect(plus, contains("selected['free_delivery'] == true"));
    expect(plus, isNot(contains("Text('VISA")));
    expect(plus, isNot(contains("Text('MASTERCARD")));
  });

  test('Delivery labels use Restaurantes, not Mercado', () {
    final page = File('lib/express_delivery_v2_page.dart').readAsStringSync();
    final marketLegacy =
        File('lib/express_marketplace_page.dart').readAsStringSync();
    expect(page, contains("label: 'Restaurantes'"));
    expect(page, isNot(contains("label: 'Mercados'")));
    expect(marketLegacy, isNot(contains("'Express Market'")));
  });
}

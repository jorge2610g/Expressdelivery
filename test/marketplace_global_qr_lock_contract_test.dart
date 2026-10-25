import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one pending QR is reused and only blocks orders in its own channel', () {
    final sql = File(
      'supabase/migrations/20261025124900_marketplace_global_qr_order_checkout.sql',
    ).readAsStringSync();
    final edge = File(
      'supabase/functions/marketplace-payments/index.ts',
    ).readAsStringSync();
    final api = File('lib/services/express_service.dart').readAsStringSync();

    expect(sql, contains('on public.marketplace_orders(customer_id,channel)'));
    expect(sql, contains("and channel=new.channel"));
    expect(sql, contains('public.marketplace_pending_global_qr_order()'));
    expect(sql, contains("payment_status='qr_pending'"));
    expect(sql, contains("v_order.payment_status<>'qr_pending' then"));
    expect(sql, contains("v_order_json:=v_order_json-'online_checkout_url'"));
    expect(edge, contains("if (claim?.state === 'ready')"));
    expect(edge, contains('reused:true'));
    expect(
      api,
      contains("supabase.rpc('marketplace_pending_global_qr_order')"),
    );
  });

  test(
    'checkout resumes the existing QR and cancellation releases the app lock',
    () {
      final page = File('lib/express_delivery_v2_page.dart').readAsStringSync();
      final sql = File(
        'supabase/migrations/20261025124900_marketplace_global_qr_order_checkout.sql',
      ).readAsStringSync();
      final edge = File(
        'supabase/functions/marketplace-payments/index.ts',
      ).readAsStringSync();

      expect(page, contains('_resumePendingGlobalQrOrder()'));
      expect(page, contains('Te llevo a ese pedido.'));
      expect(page, contains('Deshabilitar QR'));
      expect(page, contains('Se deshabilitará este QR para este pedido'));
      expect(page, contains('VeriPagos no anula el código'));
      expect(sql, contains("set payment_status=p_status,status='cancelled'"));
      expect(sql, contains("'disabled'"));
      expect(
        sql,
        contains(
          "if p_status not in ('paid','cancelled','expired','disabled') then",
        ),
      );
      expect(edge, contains("p_status:'disabled'"));
      expect(sql, contains("and o.payment_status='qr_pending'"));
    },
  );
}

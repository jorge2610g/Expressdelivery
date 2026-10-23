import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261023192321_enforce_admin_adjustment_debt.sql',
  ).readAsStringSync();
  final gateway = File(
    'supabase/functions/driver-wallet-gateway/index.ts',
  ).readAsStringSync();

  test(
    'passenger Taxi requests are blocked without interrupting parcel flow',
    () {
      expect(migration, contains('guard_ride_request_cancellation_debt()'));
      expect(migration, contains('admin_wallet_adjustment_debts d'));
      expect(
        migration,
        contains(
          "if coalesce(new.service_mode,'taxi')<>'taxi' then return new; end if;",
        ),
      );
      expect(
        migration,
        isNot(
          contains('delivery_request_guard_passenger_admin_adjustment_debt'),
        ),
      );
    },
  );

  test(
    'drivers cannot go online or accept Taxi and Delivery work with debt',
    () {
      expect(migration, contains('driver_online_adjustment_debt'));
      expect(migration, contains('driver_offers_guard_cancellation_debt'));
      expect(migration, contains('trips_guard_driver_cancellation_debt'));
      expect(
        migration,
        contains('delivery_offers_guard_admin_adjustment_debt'),
      );
      expect(migration, contains('delivery_claim_guard_admin_adjustment_debt'));
      expect(migration, contains('force_driver_offline_for_admin_debt'));
    },
  );

  test('verified wallet payments pay administrative debts FIFO', () {
    expect(migration, contains('apply_admin_adjustment_debt_credit'));
    expect(migration, contains("'admin_adjustment_debt_paid',v_debt_paid"));
    expect(migration, contains('to service_role'));
    expect(
      migration,
      contains('v_item.provider_order_id<>p_provider_order_id'),
    );
    expect(migration, contains('v_item.amount<>round(p_verified_amount,2)'));
    expect(
      migration,
      contains('v_item.currency_code<>upper(trim(p_verified_currency))'),
    );
  });

  test('Preview payments are simulated and the debt helper stays private', () {
    expect(
      migration,
      contains(
        'revoke all on function public.has_pending_admin_adjustment_debt',
      ),
    );
    expect(migration, contains('preview_settle_admin_adjustment_debts_v1'));
    expect(
      migration,
      contains("set_config('app.runtime_channel','preview',true)"),
    );
  });

  test('passengers can open a verified top-up only to pay their debt', () {
    expect(gateway, contains('admin_wallet_adjustment_debts'));
    expect(gateway, contains(".eq('country_code',context.country_code)"));
    expect(
      gateway,
      contains(".eq('channel','production').gt('remaining_amount',0)"),
    );
    expect(gateway, contains('regularizar un ajuste pendiente'));
  });
}

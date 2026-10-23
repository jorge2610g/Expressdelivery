import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261023170100_fix_cancellation_debt_gateway_role.sql',
  ).readAsStringSync();
  final routine = sql.substring(sql.indexOf('create or replace function'));

  test('service-role-only execute permission is the RPC authorization gate', () {
    expect(sql, contains('from public,anon,authenticated'));
    expect(sql, contains('to service_role'));
    expect(routine, isNot(contains('request.jwt.claim.role')));
  });

  test('keeps provider amount and production binding checks before settlement', () {
    expect(sql, contains('v_item.provider_order_id<>p_provider_order_id'));
    expect(sql, contains('v_item.amount<>round(p_verified_amount,2)'));
    expect(sql, contains('v_item.currency_code<>upper(trim(p_verified_currency))'));
    expect(sql, contains("b.environment='production'"));
    expect(sql, contains('public.is_active_audit_user(v_item.user_id)'));
  });

  test('marks only the attached unpaid debts and the checkout as paid', () {
    expect(sql, contains('id=any(v_item.cancellation_debt_ids)'));
    expect(sql, contains('paid_at is null'));
    expect(sql, contains("set status='paid',paid_at=now()"));
    expect(sql, contains('v_total<>v_item.amount'));
  });
}

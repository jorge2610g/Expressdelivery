import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Production parcel grants are scoped to an approved administrator', () {
    final sql = File(
      'supabase/migrations/20261014022500_production_parcel_vehicle_grant_and_dispatch.sql',
    ).readAsStringSync();
    expect(sql, contains('public.is_admin()'));
    expect(sql, contains('public.admin_assert_target_environment(p_driver_id,p_channel)'));
    expect(sql, contains('dv.is_active=true'));
    expect(sql, contains('public.parcel_vehicle_capacity(v_vehicle_type)'));
    expect(sql, contains('public.parcel_kind_capacity(p_parcel_kind)'));
    expect(sql, isNot(contains("p_channel is distinct from 'preview'")));
  });

  test('Restore availability only for already enabled and passenger-visible zones',
      () {
    final sql = File(
      'supabase/migrations/20261014022500_production_parcel_vehicle_grant_and_dispatch.sql',
    ).readAsStringSync();
    expect(sql, contains("zc.service_key in ('parcel','delivery')"));
    expect(sql, contains('zc.enabled=true'));
    expect(sql, contains('zc.passenger_visible=true'));
    expect(sql, contains('z.active=true'));
    expect(sql, isNot(contains('insert into public.driver_parcel_vehicle_grants')));
  });
}

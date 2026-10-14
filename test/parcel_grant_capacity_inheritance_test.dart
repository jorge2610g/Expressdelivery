import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261014032000_parcel_grant_capacity_inheritance.sql',
  ).readAsStringSync();

  int capacity(String kind) => switch (kind) {
        'moto' => 1,
        'auto' => 2,
        'carga' => 3,
        _ => 999,
      };
  bool eligible({
    required String vehicle,
    required String? approvedMax,
    required String requested,
  }) =>
      approvedMax != null &&
      capacity(vehicle) >= capacity(requested) &&
      capacity(approvedMax) >= capacity(requested);

  test('authorization matrix supports lower-size packages', () {
    expect(eligible(vehicle: 'moto', approvedMax: 'moto', requested: 'moto'), true);
    expect(eligible(vehicle: 'moto', approvedMax: 'moto', requested: 'auto'), false);
    expect(eligible(vehicle: 'auto', approvedMax: 'auto', requested: 'moto'), true);
    expect(eligible(vehicle: 'auto', approvedMax: 'auto', requested: 'auto'), true);
    expect(eligible(vehicle: 'auto', approvedMax: 'auto', requested: 'carga'), false);
    expect(eligible(vehicle: 'auto', approvedMax: 'moto', requested: 'auto'), false);
    expect(eligible(vehicle: 'carga', approvedMax: 'carga', requested: 'moto'), true);
    expect(eligible(vehicle: 'carga', approvedMax: 'carga', requested: 'auto'), true);
    expect(eligible(vehicle: 'carga', approvedMax: 'carga', requested: 'carga'), true);
    expect(eligible(vehicle: 'auto', approvedMax: null, requested: 'moto'), false);
  });

  test('SQL uses max grant capacity and preserves all security constraints', () {
    expect(sql, contains('public.parcel_kind_capacity(g.parcel_kind)'));
    expect(sql, contains('>= public.parcel_kind_capacity(r.parcel_kind)'));
    expect(sql, isNot(contains('g.parcel_kind=r.parcel_kind')));
    expect(sql, contains('join public.driver_parcel_vehicle_grants g'));
    expect(sql, contains('g.enabled'));
    expect(sql, contains('dv.is_active=true'));
    expect(sql, contains('wp.status=\'approved\''));
    expect(sql, contains('public.admin_user_runtime_environment(dp.id)=r.channel'));
    expect(sql, contains('dp.id=p_driver_id and dp.zone_id=r.zone_id'));
    expect(sql, contains('public.parcel_vehicle_capacity(dv.vehicle_type)'));
    expect(sql, isNot(contains('insert into public.driver_parcel_vehicle_grants')));
    expect(sql, isNot(contains('update public.driver_parcel_vehicle_grants')));
    expect(sql, contains('from public,anon,authenticated'));
  });
}

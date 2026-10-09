import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_registration_status_watcher.dart';

void main() {
  test('driver registration approval changes invalidate the visible status', () {
    final before = <String, dynamic>{
      'approval_status': 'pending',
      'online_status': 'offline',
      'zone_id': 'iquique',
      'country_code': 'CL',
      'onboarding_completed_at': '2026-10-09',
    };
    final after = <String, dynamic>{...before, 'approval_status': 'approved'};
    expect(
      DriverRegistrationStatusWatcher.profileStatusSignature(before),
      isNot(DriverRegistrationStatusWatcher.profileStatusSignature(after)),
    );
  });

  test('GPS changes do not refetch registration or documents', () {
    final before = <String, dynamic>{
      'approval_status': 'pending',
      'online_status': 'offline',
      'zone_id': 'trinidad',
      'latitude': -14.0,
      'longitude': -64.9,
      'heading_degrees': 12,
      'updated_at': '2026-10-09T12:00:00Z',
    };
    final after = <String, dynamic>{
      ...before,
      'latitude': -14.1,
      'longitude': -64.8,
      'heading_degrees': 40,
      'updated_at': '2026-10-09T12:00:02Z',
    };
    expect(
      DriverRegistrationStatusWatcher.profileStatusSignature(before),
      DriverRegistrationStatusWatcher.profileStatusSignature(after),
    );
  });

  test('a change of zone or online state refreshes driver details', () {
    final before = <String, dynamic>{
      'approval_status': 'approved',
      'online_status': 'offline',
      'zone_id': 'trinidad',
    };
    final online = <String, dynamic>{...before, 'online_status': 'online'};
    final changedZone = <String, dynamic>{...before, 'zone_id': 'iquique'};
    final signature = DriverRegistrationStatusWatcher.profileStatusSignature(before);
    expect(DriverRegistrationStatusWatcher.profileStatusSignature(online), isNot(signature));
    expect(DriverRegistrationStatusWatcher.profileStatusSignature(changedZone), isNot(signature));
  });
}

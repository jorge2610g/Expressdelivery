import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passenger trip card loads union identity for display beside driver details', () {
    final source = File('lib/video_style_home.dart').readAsStringSync();
    expect(source, contains("'driver_partner_public_identity'"));
    expect(source, contains(r"'SOCIOS ${partnerIdentity!['member_number']}'"));
    expect(source, contains("partnerIdentity!['partner_name']"));
    expect(source, contains("partnerIdentity!['brand_color']"));
  });

  test('syndicate records and completed plan reports remain environment scoped', () {
    final sql = File(
      'supabase/migrations/20261031062041_syndicate_member_identity_and_period_dashboard.sql',
    ).readAsStringSync();
    expect(sql, contains("pay.status='approved' and pay.channel=v_channel"));
    expect(sql, contains("pay.status='approved' and pay.channel='production'"));
    expect(sql, contains("m.channel=v_channel and m.status in ('active','suspended')"));
    expect(sql, contains('partner_approve_join_request'));
    expect(sql, contains('partner_set_membership_status'));
  });
}

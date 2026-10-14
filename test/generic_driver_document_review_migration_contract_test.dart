import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generic document review is admin-guarded and refuses stale photo approval', () {
    final sql = File('supabase/migrations/20261015000500_generic_driver_document_photo_review_v2.sql').readAsStringSync();
    expect(sql, contains("if not public.is_admin() then"));
    expect(sql, contains('admin_assert_target_environment(v_doc.driver_id,v_channel)'));
    expect(sql, contains("p_channel text default null"));
    expect(sql, contains("if v_path is distinct from case v_slot"));
    expect(sql, contains("driver_license"));
    expect(sql, contains("v_parts := coalesce(old.review_parts"));
    expect(sql, contains("'driver_auto_approved',false"));
    expect(sql, contains('p_expected_version is null'));
    expect(sql, contains('trg_driver_generic_document_part_states'));
    expect(sql, contains('revoke all on function public.admin_driver_document_review_part_v2'));
    expect(sql, isNot(contains('perform public.driver_auto_approve_if_complete')));
    expect(sql, isNot(contains('alter table public.driver_profiles')));
  });
}

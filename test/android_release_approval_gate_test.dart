import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paired APK+AAB internal release requires owner authorization and exact job', () {
    final workflow = File('.github/workflows/build-android.yml').readAsStringSync();
    final playUpload = File('scripts/play_internal_upload.py').readAsStringSync();
    expect(workflow, contains("inputs.confirm_candidate == 'AUTORIZO APK+AAB PRUEBAS INTERNAS'"));
    expect(workflow, contains("inputs.job_id != ''"));
    expect(workflow, contains('JOB_ARTIFACT" != "single-app-candidate-apk+aab"'));
    expect(workflow, contains('Verify Google Play Internal connection and versionCode'));
    expect(workflow, contains('Upload the paired AAB to Google Play Internal'));
    expect(workflow, contains('steps.claim.outputs.source_sha'));
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, isNot(contains("cron: '*/5 * * * *'")));
    expect(workflow, isNot(contains("  push:\n    paths:")));
    expect(workflow, contains(r'if [ "$PACKAGE_BUILD_NUMBER" != "$REQUESTED_BUILD_NUMBER" ]; then'));
    expect(workflow, contains(r'if [ "$ACTUAL_SHA" !='));
    expect(workflow, contains('com.express.usuario1'));
    expect(workflow, contains('apk_sha256'));
    expect(workflow, contains('aab_sha256'));
    expect(workflow, contains('identity_manifest_sha256'));
    expect(playUpload, contains('tracks/internal'));
    expect(playUpload, isNot(contains('/tracks/production')));
    expect(playUpload, contains('AUTORIZO APK+AAB PRUEBAS INTERNAS'));
  });
  test('planned Android source version matches the 142 candidate', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.6.3+142'));
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paired APK+AAB internal release requires owner authorization and exact job', () {
    final workflow = File('.github/workflows/build-android.yml').readAsStringSync();
    final playUpload = File('scripts/play_internal_upload.py').readAsStringSync();
    expect(workflow, contains('confirm_emulator_qa:'));
    expect(workflow, contains("inputs.confirm_emulator_qa == 'QA EMULADORES OK'"));
    expect(workflow, contains("inputs.confirm_emulator_qa == 'QA PENDIENTE - PRUEBA MANUAL EN INTERNAL'"));
    expect(workflow, contains('Record manual Internal QA as pending'));
    expect(workflow, contains('This is not an emulator QA pass and does not authorize Production promotion.'));
    expect(workflow, contains("inputs.confirm_candidate == 'AUTORIZO APK+AAB PRUEBAS INTERNAS'"));
    expect(workflow.indexOf('confirm_emulator_qa:'), lessThan(workflow.indexOf('confirm_candidate:')));
    expect(workflow, contains("inputs.job_id != ''"));
    expect(workflow, contains('JOB_ARTIFACT" != "single-app-candidate-apk+aab"'));
    expect(workflow, contains('Verify Google Play Internal connection and versionCode'));
    expect(workflow, contains('Upload the paired AAB to Google Play Internal'));
    expect(workflow, contains('steps.claim.outputs.source_sha'));
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains("cron: '*/5 * * * *'"));
    expect(workflow, contains("github.event_name == 'schedule'"));
    expect(workflow, contains("github.actor_id == '197861476'"));
    expect(workflow, contains('.github/build-requests/android-internal.json'));
    expect(workflow, contains('queue_internal_candidate'));
    expect(workflow, contains('REQUESTED_VERSION_NAME'));
    expect(workflow, contains('PLAY_INTERNAL_CONFIRMATION'));
    expect(workflow, isNot(contains("  push:\n    paths:")));
    expect(workflow, contains(r'if [ "$PACKAGE_BUILD_NUMBER" != "$REQUESTED_BUILD_NUMBER" ]; then'));
    expect(workflow, contains(r'if [ "$ACTUAL_SHA" !='));
    expect(workflow, contains('com.express.usuario1'));
    expect(workflow, contains('apk_sha256'));
    expect(workflow, contains('aab_sha256'));
    expect(playUpload, contains('tracks/internal'));
    expect(playUpload, isNot(contains('/tracks/production')));
    expect(playUpload, contains('AUTORIZO APK+AAB PRUEBAS INTERNAS'));
  });
  test('planned Android source version matches the 1.6.4 build 148 candidate', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.6.4+148'));
  });
}

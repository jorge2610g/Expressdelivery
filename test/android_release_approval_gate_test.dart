import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('APK generation requires explicit owner authorization and exact job', () {
    final workflow = File('.github/workflows/build-android.yml').readAsStringSync();
    expect(workflow, contains("confirm_candidate == 'AUTORIZO APK QA'"));
    expect(workflow, contains("inputs.job_id != ''"));
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, isNot(contains("cron: '*/5 * * * *'")));
    expect(workflow, isNot(contains("  push:\n    paths:")));
    expect(workflow, contains(r'if [ "$PACKAGE_BUILD_NUMBER" != "$REQUESTED_BUILD_NUMBER" ]; then'));
    expect(workflow, contains(r'if [ "$ACTUAL_SHA" !='));
    expect(workflow, contains('com.express.usuario1'));
    expect(workflow, contains('apk_sha256'));
    expect(workflow, contains('aab_sha256'));
    expect(workflow, contains('identity_manifest_sha256'));
    expect(workflow.toLowerCase(), contains('no publicar en play'));
  });
  test('next Android source version matches backend reserved Play candidate', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.6.2+140'));
  });
}

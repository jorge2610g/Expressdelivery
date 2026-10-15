import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android diagnostic is manual and cannot publish a public APK', () {
    final workflow = File('.github/workflows/android-overlay-qa.yml').readAsStringSync();
    final trigger = workflow.split('permissions:').first;
    expect(trigger, contains('workflow_dispatch:'));
    expect(trigger, isNot(contains('\n  push:')));
    expect(workflow, isNot(contains('actions/upload-artifact')));
    expect(workflow, contains('patch_android_gradle_qa.py'));
  });
  test('Python QA patch regression suite passes', () async {
    if (!Platform.isLinux) return;
    final run = await Process.run('python3', [
      '-m', 'unittest', 'discover', '-s', 'test',
      '-p', 'test_patch_android_gradle_qa.py'
    ]);
    expect(run.exitCode, 0, reason: run.stdout.toString() + run.stderr.toString());
  });
}

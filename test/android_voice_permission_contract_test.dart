import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official signed Android build declares required voice permissions', () {
    final workflow = File('.github/workflows/build-android.yml').readAsStringSync();
    expect(workflow, contains('android.permission.RECORD_AUDIO'));
    expect(workflow, contains('android.permission.MODIFY_AUDIO_SETTINGS'));
    expect(workflow, contains('APK_PERMISSIONS'));
    expect(workflow, contains('com.express.usuario1'));
    expect(workflow, isNot(contains('com.express.usuario.preview')));
    expect(workflow, isNot(contains('preview-apk')));
  });

  test('Android voice call requests mic at runtime before invitation', () {
    final voice = File('lib/private_voice_call.dart').readAsStringSync();
    expect(voice, contains('Permission.microphone.status'));
    expect(voice, contains('Permission.microphone.request()'));
    expect(voice, contains('zego_microphone_permission_denied'));
    expect(voice, contains('ZegoCallInvitationPermission.microphone'));
    expect(voice.indexOf('Permission.microphone.request()'),
        lessThan(voice.indexOf("final result = await _invoke({\n        'action': 'prepare'")));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official signed Android build declares required voice permissions', () {
    final workflow = File('.github/workflows/build-android.yml').readAsStringSync();
    expect(workflow, contains('android.permission.RECORD_AUDIO'));
    expect(workflow, contains('android.permission.MODIFY_AUDIO_SETTINGS'));
    expect(workflow, contains('android.permission.USE_FULL_SCREEN_INTENT'));
    // The overlay permission must be declared in the generated manifest and
    // checked by the guard, so a regenerated android/ folder cannot lose it.
    expect(
      RegExp('android.permission.SYSTEM_ALERT_WINDOW')
          .allMatches(workflow)
          .length,
      greaterThanOrEqualTo(2),
    );
    expect(workflow, contains('android:launchMode="singleInstance"'));
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
    // Both session initialization paths (login/resume and call launch)
    // must enable the same offline full-screen incoming-call UI.
    expect(RegExp('showOnLockedScreen: true').allMatches(voice).length, 2);
    expect(RegExp('showOnFullScreen: true').allMatches(voice).length, 2);
    // Background incoming calls need the overlay permission in both paths,
    // and its Spanish dialog must not reuse the microphone title.
    expect(
        RegExp('ZegoCallInvitationPermission.systemAlertWindow')
            .allMatches(voice)
            .length,
        2);
    expect(voice, contains('systemAlertWindowConfirmDialogSubTitle:'));
    expect(voice, isNot(contains("permissionConfirmDialogTitle: 'Permiso de micrófono'")));
    expect(voice.indexOf('Permission.microphone.request()'),
        lessThan(voice.indexOf("final result = await _invoke({\n        'action': 'prepare'")));
  });
}

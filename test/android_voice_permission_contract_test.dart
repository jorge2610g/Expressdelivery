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
    // Full-screen call notifications are off: Android would open its settings page
    // and Google Play restricts that permission to calling apps. Calls still ring.
    expect(RegExp('showOnLockedScreen: false').allMatches(voice).length, 2);
    expect(RegExp('showOnFullScreen: false').allMatches(voice).length, 2);
    // ZEGO must not ask for the overlay permission by itself: Express asks for it
    // once per trip, through its own message. Its Spanish dialog must not reuse the microphone title.
    expect(
        RegExp('ZegoCallInvitationPermission.systemAlertWindow')
            .allMatches(voice)
            .length,
        0);
    expect(voice, contains('systemAlertWindowConfirmDialogSubTitle:'));
    expect(voice, isNot(contains("permissionConfirmDialogTitle: 'Permiso de micrófono'")));
    expect(voice.indexOf('Permission.microphone.request()'),
        lessThan(voice.indexOf("final result = await _invoke({\n        'action': 'prepare'")));

    final sessionSync = voice.substring(
      voice.indexOf('Future<void> syncForSession()'),
      voice.indexOf('Future<void> startTripCall('),
    );
    expect(
      sessionSync,
      isNot(contains('ZegoCallInvitationPermission.microphone')),
      reason: 'Session sync must not request microphone during app startup.',
    );
    expect(
      sessionSync,
      contains('permissions: const <ZegoCallInvitationPermission>[]'),
      reason: 'An explicit empty list overrides ZEGO SDK startup defaults.',
    );
  });
}

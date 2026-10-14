import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web voice rooms are audio only and preserve native SDK controls', () {
    final src = File('web/express_voice_call.js').readAsStringSync();
    for (final name in <String>[
      'onSetRoomConfigBeforeJoining:', 'turnOnCameraWhenJoining: false',
      'turnOnMicrophoneWhenJoining: true',
      'showMyCameraToggleButton: false', 'showAudioVideoSettingsButton: false',
      'showScreenSharingButton: false', 'showNonVideoUser: false',
      'showOnlyAudioUser: false', 'showMyMicrophoneToggleButton: true',
      'autoHideFooter: false', "view.className = 'express-phone-view'",
      'pointer-events: none', 'onJoinRoom: () => displayPhoneView()',
      'onLeaveRoom: () => removePhoneView()', 'onCallInvitationEnded:',
      'instance.addPlugins({ZIM: window.ZIM})', 'sendCallInvitation(options)',
    ]) {
      expect(src, contains(name));
    }
    expect(src, isNot(contains('getUserMedia(')));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web uses a distinct browser-call kit, never Flutter native engine', () {
    final html = File('web/index.html').readAsStringSync();
    final js = File('web/express_voice_call.js').readAsStringSync();
    expect(html, contains('express_voice_call.js'));
    expect(js, contains('generateKitTokenForProduction'));
    expect(js, contains('InvitationTypeVoiceCall'));
    expect(js, contains('sendCallInvitation'));
    expect(js, contains('enableNotifyWhenAppRunningInBackgroundOrQuit: true'));
    expect(js, contains('roomID: callID'));
    expect(js, isNot(contains('generateKitTokenForTest')));
    expect(js, isNot(contains('generateKitTokenForTest(')));
  });

  test('Express web calls use phone-style voice UI without video tiles', () {
    final html = File('web/index.html').readAsStringSync();
    final ui = File('web/express_voice_ui.js').readAsStringSync();
    final css = File('web/express_voice_ui.css').readAsStringSync();
    final adapter = File('web/express_voice_call.js').readAsStringSync();
    expect(html, contains('express_voice_ui.css'));
    expect(html, contains('express_voice_ui.js'));
    expect(adapter, contains('ExpressVoiceUI?.invitationOptions()'));
    expect(ui, contains('enableCustomCallInvitationWaitingPage: true'));
    expect(ui, contains('enableCustomCallInvitationDialog: true'));
    expect(ui, contains('onWaitingPageWhenSending'));
    expect(ui, contains('onConfirmDialogWhenReceiving'));
    expect(ui, contains('onSetRoomConfigBeforeJoining'));
    expect(ui, contains('turnOnCameraWhenJoining: false'));
    expect(ui, contains('showMyCameraToggleButton: false'));
    expect(ui, contains('showScreenSharingButton: false'));
    expect(ui, contains('showOnlyAudioUser: false'));
    expect(ui, contains('showNonVideoUser: false'));
    expect(ui, contains('showMyMicrophoneToggleButton: true'));
    expect(ui, contains('requireRoomForegroundView: roomForeground'));
    expect(ui, contains('onLeaveRoom: clearPresentation'));
    expect(css, contains('.express-voice-room-foreground'));
    expect(ui, isNot(contains('generateKitTokenForTest')));
  });

  test('browser/Android functions are separated at compile time', () {
    final dart = File('lib/private_voice_call.dart').readAsStringSync();
    expect(dart, contains("if (dart.library.js_interop)"));
    expect(dart, contains('initializeExpressBrowserVoice'));
    expect(dart, contains('sendExpressBrowserVoice'));
    expect(dart, contains('if (kIsWeb)'));
    // Browser call setup must be first, including the trip-scoped token.
    // Otherwise the native Flutter ZEGO engine gets initialized on Chrome.
    final tripCall = dart.substring(dart.indexOf('Future<void> startTripCall('));
    expect(tripCall, contains('final ready = await browser_voice.initializeExpressBrowserVoice('));
    expect(tripCall, contains('} else if (!_initialized ||'));
    final webInitIndex = tripCall.indexOf('final ready = await browser_voice.initializeExpressBrowserVoice(');
    final nativeInitIndex = tripCall.indexOf('ZegoUIKitPrebuiltCallInvitationService().init(');
    expect(webInitIndex, greaterThanOrEqualTo(0));
    expect(nativeInitIndex, greaterThan(webInitIndex));
  });
}

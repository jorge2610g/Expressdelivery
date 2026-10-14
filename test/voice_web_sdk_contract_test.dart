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

  test('fresh server tokens do not interrupt the same web ZIM identity', () {
    final js = File('web/express_voice_call.js').readAsStringSync();
    expect(js, contains('currentAppID === Number(appID)'));
    expect(js, contains('SESSION_REFRESH_MS'));
    expect(js, contains('currentToken = token; // Fresh token retained for recovery'));
    expect(js, isNot(contains('currentID === userID && currentToken === token')));
    expect(js, contains('6000121'));
    expect(js, contains('voice_zim_not_connected'));
    expect(js, contains('if (!wasSignedOut(error)) throw error'));
    expect(js, contains('forgetKit();'));
    // No secret or test tokens are ever generated in the browser.
    expect(js, isNot(contains('generateKitTokenForTest(')));
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

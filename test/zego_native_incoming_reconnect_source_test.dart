import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Call Kit is considered ready only when ZEGO signaling is connected', () {
    final source = File('lib/private_voice_call.dart').readAsStringSync();
    expect(source, contains('ZegoSignalingPluginConnectionState.connected'));
    expect(source, contains('_waitForNativeSignalingConnected()'));
    expect(source, contains('zego_signaling_reconnect_attempt'));
    expect(source, contains('await uninitialize();'));
    expect(source, contains('if (!kIsWeb && !await _waitForNativeSignalingConnected())'));
    expect(source, contains('isInCalling'));
  });

  test('native calling session is checked again when app resumes', () {
    final source = File('lib/mobile_main.dart').readAsStringSync();
    expect(source, contains('with WidgetsBindingObserver'));
    expect(source, contains('WidgetsBinding.instance.addObserver(this)'));
    expect(source, contains('WidgetsBinding.instance.removeObserver(this)'));
    expect(source, contains('state == AppLifecycleState.resumed'));
    expect(source, contains('unawaited(_syncPrivateVoiceCallSafely())'));
  });
}

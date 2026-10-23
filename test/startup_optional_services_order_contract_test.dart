import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native optional services wait until startup permission gate is ready',
    () {
      final mobile = File('lib/mobile_main.dart').readAsStringSync();
      final gate = File('lib/startup_permission_gate.dart').readAsStringSync();

      final mobileEntrypoint = mobile.substring(
        mobile.indexOf('void runExpressMobile()'),
        mobile.indexOf('class ExpressMobileApp'),
      );
      expect(
        mobileEntrypoint,
        isNot(contains('initializeExpressOptionalMobileServices(')),
      );
      expect(
        mobileEntrypoint,
        isNot(contains('_syncPrivateVoiceCallSafely()')),
      );
      expect(mobile, contains('onReady: _onStartupPermissionsReady'));
      expect(mobile, contains('void _onStartupPermissionsReady()'));
      expect(gate, contains('_notifyReady();'));
      expect(gate, contains('_readyCallbackSent = true;'));
      expect(gate, isNot(contains('pushPermissionState()')));
      expect(gate, isNot(contains('enablePushNotifications(')));
      expect(gate, contains('_ready = true;'));
    },
  );
}

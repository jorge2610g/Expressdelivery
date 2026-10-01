import 'dart:async';

Future<String> pushPermissionState() async => 'unsupported';

Future<bool> enablePushNotifications(String accessToken) async => false;

Future<void> disablePushNotifications(String accessToken) async {}

void startExpressAlertSound({int durationSeconds = 15}) {}

void stopExpressAlertSound() {}


Stream<String> expressForegroundPushEvents() => const Stream<String>.empty();

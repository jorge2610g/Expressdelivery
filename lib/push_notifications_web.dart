import 'dart:js' as js;
import 'dart:js_util' as js_util;

Future<String> pushPermissionState() async {
  try {
    final value = js.context.callMethod('expressPushPermissionState');
    return value?.toString() ?? 'unsupported';
  } catch (_) {
    return 'unsupported';
  }
}

Future<bool> enablePushNotifications(String accessToken) async {
  try {
    final promise = js.context.callMethod(
      'expressEnablePush',
      <Object?>[accessToken],
    );
    final result = await js_util.promiseToFuture<Object?>(promise);
    if (result == null) return false;
    final ok = js_util.getProperty<Object?>(result, 'ok');
    return ok == true;
  } catch (_) {
    return false;
  }
}

Future<void> disablePushNotifications(String accessToken) async {
  try {
    final promise = js.context.callMethod(
      'expressDisablePush',
      <Object?>[accessToken],
    );
    await js_util.promiseToFuture<Object?>(promise);
  } catch (_) {}
}

void startExpressAlertSound({int durationSeconds = 15}) {
  try {
    js.context.callMethod(
      'expressStartAlertTone',
      <Object?>[durationSeconds.clamp(1, 15)],
    );
  } catch (_) {}
}

void stopExpressAlertSound() {
  try {
    js.context.callMethod('expressStopAlertTone');
  } catch (_) {}
}

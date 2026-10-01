import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;

Future<void> initializePushPlatform({String? packageName}) async {}

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


final StreamController<String> _expressForegroundPushController =
    StreamController<String>.broadcast();
bool _expressForegroundPushListenerReady = false;

Stream<String> expressForegroundPushEvents() {
  if (!_expressForegroundPushListenerReady) {
    _expressForegroundPushListenerReady = true;
    html.window.onMessage.listen((event) {
      final data = event.data;
      if (data is! String) return;
      const prefix = 'EXPRESS_PUSH_EVENT:';
      if (!data.startsWith(prefix)) return;
      final type = data.substring(prefix.length).trim();
      _expressForegroundPushController.add(
        type.isEmpty ? 'general' : type,
      );
    });
  }
  return _expressForegroundPushController.stream;
}

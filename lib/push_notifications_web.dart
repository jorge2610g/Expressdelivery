import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';

@JS('expressPushPermissionState')
external JSAny? _expressPushPermissionState();

@JS('expressEnablePush')
external JSPromise<_ExpressPushResult?> _expressEnablePush(JSString accessToken);

@JS('expressDisablePush')
external JSPromise<JSAny?> _expressDisablePush(JSString accessToken);

@JS('expressStartAlertTone')
external void _expressStartAlertTone(JSNumber durationSeconds);

@JS('expressStopAlertTone')
external void _expressStopAlertTone();

@JS()
extension type _ExpressPushResult._(JSObject _) implements JSObject {
  external JSBoolean? get ok;
}

class ExpressPushEvent {
  const ExpressPushEvent({
    required this.type,
    this.notificationId,
    this.rideRequestId,
    this.offerId,
    this.zoneId,
    this.mode,
    this.deepLink,
    this.opened = false,
  });

  final String type;
  final String? notificationId;
  final String? rideRequestId;
  final String? offerId;
  final String? zoneId;
  final String? mode;
  final String? deepLink;
  final bool opened;
}

Future<void> initializePushPlatform({String? packageName}) async {}

Future<String> pushPermissionState() async {
  try {
    final value = _expressPushPermissionState();
    return value?.dartify()?.toString() ?? 'unsupported';
  } catch (_) {
    return 'unsupported';
  }
}

Future<bool> enablePushNotifications(String accessToken) async {
  try {
    final result = await _expressEnablePush(accessToken.toJS).toDart;
    return result?.ok?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> disablePushNotifications(String accessToken) async {
  try {
    await _expressDisablePush(accessToken.toJS).toDart;
  } catch (_) {}
}

void startExpressAlertSound({int durationSeconds = 15}) {
  try {
    _expressStartAlertTone(durationSeconds.clamp(1, 15).toJS);
  } catch (_) {}
}

void stopExpressAlertSound() {
  try {
    _expressStopAlertTone();
  } catch (_) {}
}

final StreamController<String> _expressForegroundPushController =
    StreamController<String>.broadcast();
final StreamController<ExpressPushEvent> _expressPushEventController =
    StreamController<ExpressPushEvent>.broadcast();
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
      final normalizedType = type.isEmpty ? 'general' : type;
      _expressForegroundPushController.add(normalizedType);
      _expressPushEventController.add(
        ExpressPushEvent(type: normalizedType),
      );
    });
  }
  return _expressForegroundPushController.stream;
}

Stream<ExpressPushEvent> expressPushEvents() {
  expressForegroundPushEvents();
  return _expressPushEventController.stream;
}

ExpressPushEvent? takePendingExpressPushEvent() => null;

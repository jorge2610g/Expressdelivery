import 'dart:async';

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

Future<String> pushPermissionState() async => 'unsupported';

Future<bool> enablePushNotifications(String accessToken) async => false;

Future<void> disablePushNotifications(String accessToken) async {}

void startExpressAlertSound({int durationSeconds = 15}) {}

void stopExpressAlertSound() {}


Stream<String> expressForegroundPushEvents() => const Stream<String>.empty();


Stream<ExpressPushEvent> expressPushEvents() =>
    const Stream<ExpressPushEvent>.empty();

ExpressPushEvent? takePendingExpressPushEvent() => null;

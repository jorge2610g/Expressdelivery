import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _firebaseApiKey =
    String.fromEnvironment('EXPRESS_FIREBASE_API_KEY');
const _firebaseAppId =
    String.fromEnvironment('EXPRESS_FIREBASE_APP_ID');
const _firebaseMessagingSenderId =
    String.fromEnvironment('EXPRESS_FIREBASE_MESSAGING_SENDER_ID');
const _firebaseProjectId =
    String.fromEnvironment('EXPRESS_FIREBASE_PROJECT_ID');
const _firebaseStorageBucket =
    String.fromEnvironment('EXPRESS_FIREBASE_STORAGE_BUCKET');

final StreamController<String> _foregroundPushController =
    StreamController<String>.broadcast();

bool _firebaseReady = false;
bool _messageStreamsBound = false;
Timer? _alertTimer;
Timer? _alertStopTimer;

bool get _firebaseConfigured =>
    _firebaseApiKey.isNotEmpty &&
    _firebaseAppId.isNotEmpty &&
    _firebaseMessagingSenderId.isNotEmpty &&
    _firebaseProjectId.isNotEmpty;

FirebaseOptions get _firebaseOptions => FirebaseOptions(
      apiKey: _firebaseApiKey,
      appId: _firebaseAppId,
      messagingSenderId: _firebaseMessagingSenderId,
      projectId: _firebaseProjectId,
      storageBucket:
          _firebaseStorageBucket.isEmpty ? null : _firebaseStorageBucket,
    );

String _messageType(RemoteMessage message) {
  final type = message.data['type']?.toString().trim();
  if (type != null && type.isNotEmpty) return type;
  return 'general';
}

Future<void> _registerCurrentToken(String token) async {
  if (token.isEmpty) return;
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return;

  try {
    await Supabase.instance.client.rpc(
      'register_native_push_token',
      params: {
        'p_token': token,
        'p_platform': 'android',
        'p_device_label': 'Express Android',
      },
    );
  } catch (_) {
    // Se vuelve a intentar en el siguiente arranque/refresco de token.
  }
}

@pragma('vm:entry-point')
Future<void> _expressFirebaseBackgroundHandler(RemoteMessage message) async {
  if (!_firebaseConfigured) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: _firebaseOptions);
  }
}

Future<bool> _ensureFirebaseReady() async {
  if (!_firebaseConfigured) return false;
  if (!_firebaseReady) {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _firebaseOptions);
    }
    FirebaseMessaging.onBackgroundMessage(
      _expressFirebaseBackgroundHandler,
    );
    _firebaseReady = true;
  }

  if (!_messageStreamsBound) {
    _messageStreamsBound = true;

    FirebaseMessaging.onMessage.listen((message) {
      _foregroundPushController.add(_messageType(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _foregroundPushController.add(_messageType(message));
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_registerCurrentToken(token));
    });

    final initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      scheduleMicrotask(() {
        _foregroundPushController.add(_messageType(initialMessage));
      });
    }
  }

  return true;
}

Future<void> initializePushPlatform() async {
  try {
    await _ensureFirebaseReady();
  } catch (_) {
    // La app debe seguir arrancando aunque Firebase todavía no esté configurado.
  }
}

Future<String> pushPermissionState() async {
  try {
    if (!await _ensureFirebaseReady()) return 'unsupported';
    final settings =
        await FirebaseMessaging.instance.getNotificationSettings();
    switch (settings.authorizationStatus) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return 'granted';
      case AuthorizationStatus.denied:
        return 'denied';
      case AuthorizationStatus.notDetermined:
        return 'default';
    }
  } catch (_) {
    return 'unsupported';
  }
}

Future<bool> enablePushNotifications(String accessToken) async {
  try {
    if (!await _ensureFirebaseReady()) return false;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return false;
    await _registerCurrentToken(token);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> disablePushNotifications(String accessToken) async {
  try {
    if (!await _ensureFirebaseReady()) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc(
          'unregister_native_push_token',
          params: {'p_token': token},
        );
      } catch (_) {}
    }
    await FirebaseMessaging.instance.deleteToken();
  } catch (_) {}
}

void startExpressAlertSound({int durationSeconds = 15}) {
  stopExpressAlertSound();
  final seconds = durationSeconds.clamp(1, 15);

  void pulse() {
    unawaited(SystemSound.play(SystemSoundType.alert));
  }

  pulse();
  _alertTimer = Timer.periodic(
    const Duration(milliseconds: 850),
    (_) => pulse(),
  );
  _alertStopTimer = Timer(
    Duration(seconds: seconds),
    stopExpressAlertSound,
  );
}

void stopExpressAlertSound() {
  _alertTimer?.cancel();
  _alertTimer = null;
  _alertStopTimer?.cancel();
  _alertStopTimer = null;
}

Stream<String> expressForegroundPushEvents() {
  return _foregroundPushController.stream;
}

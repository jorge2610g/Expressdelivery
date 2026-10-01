import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_error_reporter.dart';
import 'core/supabase_client.dart';

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
String _firebasePackageName = const String.fromEnvironment(
  'EXPRESS_FIREBASE_PACKAGE_NAME',
  defaultValue: 'com.express.usuario',
);
FirebaseOptions? _resolvedFirebaseOptions;
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();
bool _localNotificationsReady = false;
Timer? _alertTimer;
Timer? _alertStopTimer;

const AndroidNotificationChannel _expressUrgentChannel =
    AndroidNotificationChannel(
  'express_urgent',
  'Viajes y ofertas Express',
  description: 'Solicitudes, ofertas y cambios importantes de tus viajes.',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

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

Future<FirebaseOptions?> _resolveFirebaseOptions() async {
  if (_firebaseConfigured) return _firebaseOptions;
  if (_resolvedFirebaseOptions != null) return _resolvedFirebaseOptions;

  try {
    final uri = Uri.parse(
      '$supabaseUrl/functions/v1/express-push-dispatch',
    ).replace(
      queryParameters: {
        'client_config': 'android',
        'package': _firebasePackageName,
      },
    );
    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return null;

    final raw = jsonDecode(response.body);
    if (raw is! Map || raw['found'] != true) return null;

    final apiKey = raw['apiKey']?.toString() ?? '';
    final appId = raw['appId']?.toString() ?? '';
    final messagingSenderId =
        raw['messagingSenderId']?.toString() ?? '';
    final projectId = raw['projectId']?.toString() ?? '';
    final storageBucket = raw['storageBucket']?.toString() ?? '';

    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }

    _resolvedFirebaseOptions = FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
    );
    return _resolvedFirebaseOptions;
  } catch (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'firebase_config',
        screen: 'push',
        eventName: 'FIREBASE_CONFIG_RESOLVE_FAILED',
      ),
    );
    return null;
  }
}

String _messageType(RemoteMessage message) {
  final type = message.data['type']?.toString().trim();
  if (type != null && type.isNotEmpty) return type;
  return 'general';
}

// Estos eventos tienen una superficie accionable dentro de Express cuando
// la app está en primer plano (tarjeta de oferta / popup de solicitud).
// Deben conservar también la notificación visible de Android, pero sin repetir
// sonido/vibración: el popup/tarjeta ya reproduce la alerta dentro de la app.
const Set<String> _foregroundActionableTypes = <String>{
  'ride_request',
  'ride_offer',
  'new_offer',
  'ride_offer_received',
};

bool _isForegroundActionableType(String type) =>
    _foregroundActionableTypes.contains(type);

Future<void> _ensureLocalNotificationsReady() async {
  if (_localNotificationsReady) return;

  const initialization = InitializationSettings(
    android: AndroidInitializationSettings('launch_background'),
  );
  await _localNotifications.initialize(settings: initialization);

  final android = _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(_expressUrgentChannel);
  _localNotificationsReady = true;
}

Future<void> _showForegroundSystemNotification(
  RemoteMessage message, {
  bool silent = false,
}) async {
  try {
    await _ensureLocalNotificationsReady();

    final notification = message.notification;
    final title = notification?.title ?? 'Express';
    final body = notification?.body ??
        message.data['body']?.toString() ??
        'Tienes una nueva actualización.';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'express_urgent',
        'Viajes y ofertas Express',
        channelDescription:
            'Solicitudes, ofertas y cambios importantes de tus viajes.',
        importance: Importance.max,
        priority: Priority.high,
        playSound: !silent,
        enableVibration: !silent,
        visibility: NotificationVisibility.public,
      ),
    );

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title: title,
      body: body,
      notificationDetails: details,
      payload: _messageType(message),
    );
  } catch (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'foreground_notification',
        screen: 'push',
        eventName: 'FOREGROUND_SYSTEM_NOTIFICATION_FAILED',
      ),
    );
    // La push continúa aunque el aviso local falle.
  }
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
  } catch (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'push_token_registration',
        screen: 'push',
        eventName: 'PUSH_TOKEN_REGISTER_FAILED',
      ),
    );
    // Se vuelve a intentar en el siguiente arranque/refresco de token.
  }
}

@pragma('vm:entry-point')
Future<void> _expressFirebaseBackgroundHandler(RemoteMessage message) async {
  final options = await _resolveFirebaseOptions();
  if (options == null) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
}

Future<bool> _ensureFirebaseReady() async {
  try {
    final options = await _resolveFirebaseOptions();
    if (options == null) {
      unawaited(
        AppErrorReporter.warning(
          'FirebaseOptions no disponibles.',
          source: 'firebase_init',
          screen: 'push',
          eventName: 'FIREBASE_OPTIONS_UNAVAILABLE',
        ),
      );
      return false;
    }

    if (!_firebaseReady) {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      FirebaseMessaging.onBackgroundMessage(
        _expressFirebaseBackgroundHandler,
      );
      _firebaseReady = true;

      // Las notificaciones locales son complementarias. Un fallo al preparar
      // el canal Android no debe impedir que Firebase obtenga permisos/token.
      unawaited(
        _ensureLocalNotificationsReady().catchError((Object error, StackTrace stack) {
          AppErrorReporter.capture(
            error,
            stack,
            source: 'local_notifications_init',
            screen: 'push',
            eventName: 'LOCAL_NOTIFICATIONS_INIT_FAILED',
          );
        }),
      );
    }

    if (!_messageStreamsBound) {
      _messageStreamsBound = true;

      FirebaseMessaging.onMessage.listen((message) {
        final type = _messageType(message);
        unawaited(
          AppErrorReporter.event(
            'FCM_FOREGROUND_RECEIVED',
            source: 'firebase_messaging',
            screen: 'push',
            context: {'type': type},
          ),
        );
        final actionable = _isForegroundActionableType(type);
        unawaited(
          AppErrorReporter.event(
            actionable
                ? 'FCM_FOREGROUND_IN_APP_ONLY'
                : 'FCM_FOREGROUND_SYSTEM_NOTIFICATION',
            source: 'firebase_messaging',
            screen: 'push',
            context: {
              'type': type,
              'system_notification_shown': !actionable,
            },
          ),
        );

        // Las solicitudes y ofertas ya tienen una superficie accionable dentro
        // de Express. Cuando la app está abierta no creamos una segunda
        // notificación Android: el popup/tarjeta y su sonido corto son la única
        // alerta. En segundo plano FCM conserva el comportamiento nativo.
        if (!actionable) {
          unawaited(_showForegroundSystemNotification(message));
        }
        _foregroundPushController.add(type);
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
  } catch (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'firebase_init',
        screen: 'push',
        eventName: 'FIREBASE_INIT_FAILED',
      ),
    );
    return false;
  }
}

Future<void> initializePushPlatform({String? packageName}) async {
  if (packageName != null && packageName.trim().isNotEmpty) {
    _firebasePackageName = packageName.trim();
    _resolvedFirebaseOptions = null;
  }
  try {
    await _ensureFirebaseReady();
  } catch (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'push_platform_init',
        screen: 'push',
        eventName: 'PUSH_PLATFORM_INIT_FAILED',
      ),
    );
    // La app debe seguir arrancando aunque Firebase todavía no esté configurado.
  }
}

Future<String> pushPermissionState() async {
  bool? androidEnabled;
  try {
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    androidEnabled = await android?.areNotificationsEnabled();
    if (androidEnabled == true) return 'granted';
  } catch (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'notification_permission_state',
        screen: 'push',
        eventName: 'ANDROID_NOTIFICATION_STATE_FAILED',
      ),
    );
  }

  try {
    if (!await _ensureFirebaseReady()) {
      return androidEnabled == false ? 'not_granted' : 'unsupported';
    }
    final settings =
        await FirebaseMessaging.instance.getNotificationSettings();
    switch (settings.authorizationStatus) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return 'granted';
      case AuthorizationStatus.denied:
      case AuthorizationStatus.deniedPermanently:
        return 'denied';
      case AuthorizationStatus.notDetermined:
        return 'default';
    }
  } catch (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'notification_permission_state',
        screen: 'push',
        eventName: 'FCM_NOTIFICATION_STATE_FAILED',
      ),
    );
    return androidEnabled == false ? 'not_granted' : 'unsupported';
  }
}

Future<bool> enablePushNotifications(String accessToken) async {
  try {
    // Android 13+ requiere disparar explícitamente POST_NOTIFICATIONS.
    // Esta petición no depende de que Firebase esté completamente listo.
    bool? androidGranted;
    try {
      await _ensureLocalNotificationsReady();
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      androidGranted = await android?.requestNotificationsPermission();

      unawaited(
        AppErrorReporter.event(
          'ANDROID_NOTIFICATION_PERMISSION_RESULT',
          source: 'push_permission',
          screen: 'push',
          context: {'granted': androidGranted},
        ),
      );
    } catch (error, stack) {
      unawaited(
        AppErrorReporter.capture(
          error,
          stack,
          source: 'push_permission',
          screen: 'push',
          eventName: 'ANDROID_NOTIFICATION_PERMISSION_REQUEST_FAILED',
        ),
      );
    }

    if (androidGranted == false) return false;

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
    if (token == null || token.isEmpty) {
      unawaited(
        AppErrorReporter.warning(
          'Firebase no devolvió token FCM.',
          source: 'push_token_registration',
          screen: 'push',
          eventName: 'FCM_TOKEN_EMPTY',
        ),
      );
      return false;
    }

    await _registerCurrentToken(token);
    unawaited(
      AppErrorReporter.event(
        'FCM_TOKEN_REGISTERED',
        source: 'push_token_registration',
        screen: 'push',
      ),
    );
    return true;
  } catch (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'push_permission',
        screen: 'push',
        eventName: 'ENABLE_PUSH_NOTIFICATIONS_FAILED',
      ),
    );
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

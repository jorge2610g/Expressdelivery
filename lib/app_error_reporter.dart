import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppErrorReporter {
  AppErrorReporter._();

  static String _environment = 'preview';
  static String? _version;
  static String? _buildNumber;
  static bool _handlersInstalled = false;
  static final Map<String, DateTime> _recentSignatures = <String, DateTime>{};

  static Future<void> configure({required bool previewMode}) async {
    _environment = previewMode ? 'preview' : 'production';
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
    } catch (_) {
      // El reporter sigue funcionando aunque PackageInfo falle.
    }
    _installGlobalHandlers();
  }

  static void _installGlobalHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
      unawaited(
        capture(
          details.exception,
          details.stack,
          source: 'flutter_framework',
          screen: 'global',
          fatal: false,
          context: {
            'library': details.library,
            'context': details.context?.toDescription(),
          },
        ),
      );
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        capture(
          error,
          stack,
          source: 'platform_dispatcher',
          screen: 'global',
          fatal: true,
        ),
      );
      return previousPlatformHandler?.call(error, stack) ?? true;
    };
  }

  static Future<void> capture(
    Object error,
    StackTrace? stack, {
    required String source,
    String? screen,
    String? eventName,
    bool fatal = false,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) async {
    await _write(
      level: fatal ? 'fatal' : 'error',
      source: source,
      eventName: eventName,
      message: error.toString(),
      stackTrace: stack?.toString(),
      screen: screen,
      context: context,
    );
  }

  static Future<void> warning(
    String message, {
    required String source,
    String? screen,
    String? eventName,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) async {
    await _write(
      level: 'warning',
      source: source,
      eventName: eventName,
      message: message,
      screen: screen,
      context: context,
    );
  }

  static Future<void> event(
    String eventName, {
    required String source,
    String? screen,
    String message = 'event',
    Map<String, dynamic> context = const <String, dynamic>{},
  }) async {
    await _write(
      level: 'info',
      source: source,
      eventName: eventName,
      message: message,
      screen: screen,
      context: context,
    );
  }

  static Future<void> _write({
    required String level,
    required String source,
    required String message,
    String? eventName,
    String? stackTrace,
    String? screen,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) async {
    final safeMessage = _truncate(message, 1600);
    final signature =
        level + '|' + source + '|' + (eventName ?? '') + '|' + safeMessage;
    final now = DateTime.now().toUtc();
    final previous = _recentSignatures[signature];
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 12)) {
      return;
    }
    _recentSignatures[signature] = now;
    if (_recentSignatures.length > 120) {
      _recentSignatures.removeWhere(
        (_, at) => now.difference(at) > const Duration(minutes: 10),
      );
    }

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      await client.from('app_error_logs').insert({
        'user_id': user.id,
        'environment': _environment,
        'level': level,
        'source': _truncate(source, 120),
        'event_name':
            eventName == null ? null : _truncate(eventName, 160),
        'message': safeMessage,
        'stack_trace':
            stackTrace == null ? null : _truncate(stackTrace, 7000),
        'screen': screen == null ? null : _truncate(screen, 160),
        'app_version': _version,
        'build_number': _buildNumber,
        'platform': kIsWeb
            ? 'web'
            : defaultTargetPlatform.toString().split('.').last,
        'context': _sanitizeMap(context),
      });
    } catch (_) {
      // Nunca dejamos que el logger provoque otro fallo en la aplicación.
    }
  }

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> input) {
    final result = <String, dynamic>{};
    for (final entry in input.entries) {
      final key = entry.key;
      final lower = key.toLowerCase();
      if (_sensitiveKey(lower)) {
        result[key] = '[redacted]';
        continue;
      }
      result[key] = _sanitizeValue(entry.value);
    }
    return result;
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) return _truncate(value, 700);
    if (value is Map) {
      return _sanitizeMap(
        value.map((key, val) => MapEntry(key.toString(), val)),
      );
    }
    if (value is Iterable) {
      return value.take(20).map(_sanitizeValue).toList();
    }
    return _truncate(value.toString(), 700);
  }

  static bool _sensitiveKey(String key) {
    if (key == 'lat' ||
        key == 'lng' ||
        key.endsWith('_lat') ||
        key.endsWith('_lng') ||
        key.contains('coordinate') ||
        key.contains('gps_position')) {
      return true;
    }

    const fragments = <String>[
      'password',
      'passwd',
      'token',
      'secret',
      'authorization',
      'apikey',
      'api_key',
      'email',
      'phone',
      'address',
      'latitude',
      'longitude',
      'location',
    ];
    return fragments.any(key.contains);
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }
}

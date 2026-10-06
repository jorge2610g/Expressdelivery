import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:terminate_restart/terminate_restart.dart';

import 'app_error_reporter.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'mobile_main.dart';
import 'push_notifications.dart';

// Express Preview is the OTA/QA entry point validated by the external auditor.
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    ExpressRuntimeChannel.previewMode = true;
    await AppErrorReporter.configure(previewMode: true);
    await prepareExpressSystemCallingUI();
    TerminateRestart.instance.initialize();

    Object? startupError;
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
        // Preview must remain bootable even if the shared_preferences
        // platform channel is unavailable. Production keeps persistent auth.
        authOptions: FlutterAuthClientOptions(
          localStorage: const EmptyLocalStorage(),
          pkceAsyncStorage: _PreviewPkceStorage(),
        ),
      );
      await initializePushPlatform(
        packageName: 'com.express.usuario.preview',
      );
    } catch (e, stack) {
      startupError = e;
      await AppErrorReporter.capture(
        e,
        stack,
        source: 'preview_startup',
        screen: 'startup',
        fatal: false,
      );
    }

    runApp(
      ExpressMobileApp(
        startupError: startupError,
        previewMode: true,
      ),
    );
  }, (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'preview_zone',
        screen: 'global',
        fatal: true,
      ),
    );
  });
}


class _PreviewPkceStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({
    required String key,
    required String value,
  }) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

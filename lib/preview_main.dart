import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:terminate_restart/terminate_restart.dart';

import 'app_error_reporter.dart';
import 'core/express_supabase_bootstrap.dart';
import 'core/runtime_channel.dart';
import 'mobile_main.dart';
import 'push_notifications.dart';
// Express Preview is the OTA/QA entry point validated by the external auditor.
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    ExpressRuntimeChannel.previewMode = true;
    await AppErrorReporter.configure(previewMode: true);
    TerminateRestart.instance.initialize();

    try {
      await prepareExpressSystemCallingUI();
    } catch (error, stack) {
      debugPrint('Express Preview calling UI bootstrap failed: $error');
      unawaited(
        AppErrorReporter.capture(
          error,
          stack,
          source: 'calling_ui_startup',
          screen: 'startup',
          fatal: false,
        ),
      );
    }

    Object? startupError;
    try {
      // QA exercises the exact same Supabase/auth bootstrap used by Production.
      await initializeExpressSupabase();
    } catch (error, stack) {
      startupError = error;
      debugPrint('Express Preview Supabase bootstrap failed: $error');
      unawaited(
        AppErrorReporter.capture(
          error,
          stack,
          source: 'preview_startup',
          screen: 'startup',
          eventName: 'SUPABASE_BOOTSTRAP_FAILED',
          fatal: false,
        ),
      );
    }

    runApp(
      ExpressMobileApp(
        startupError: startupError,
        previewMode: true,
      ),
    );

    if (startupError == null) {
      unawaited(
        initializePushPlatform(
          packageName: 'com.express.usuario.preview',
        ),
      );
    }
  }, (error, stack) {
    debugPrint('Express Preview uncaught startup/runtime error: $error');
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


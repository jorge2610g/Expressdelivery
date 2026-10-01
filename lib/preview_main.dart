import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:terminate_restart/terminate_restart.dart';

import 'app_error_reporter.dart';
import 'core/supabase_client.dart';
import 'mobile_main.dart';
import 'push_notifications.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppErrorReporter.configure(previewMode: true);
    TerminateRestart.instance.initialize();

    Object? startupError;
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
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

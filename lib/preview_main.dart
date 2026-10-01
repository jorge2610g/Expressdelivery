import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';
import 'mobile_main.dart';
import 'push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? startupError;
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
    await initializePushPlatform();
  } catch (e) {
    startupError = e;
  }

  runApp(
    ExpressMobileApp(
      startupError: startupError,
      previewMode: true,
    ),
  );
}

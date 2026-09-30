import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_entry.dart';
import 'connected_shell.dart';
import 'core/supabase_client.dart';
import 'express_splash.dart';
import 'mobile_update_gate.dart';

// Signed Android entry point for Express. Administrative UI lives only in Adminexpress.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? startupError;
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  } catch (e) {
    startupError = e;
  }

  runApp(ExpressMobileApp(startupError: startupError));
}

class ExpressMobileApp extends StatefulWidget {
  final Object? startupError;

  const ExpressMobileApp({super.key, this.startupError});

  @override
  State<ExpressMobileApp> createState() => _ExpressMobileAppState();
}

class _ExpressMobileAppState extends State<ExpressMobileApp> {
  Future<void> _logout() async {
    if (supabase.auth.currentSession != null) {
      await supabase.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Express',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => AndroidReleaseUpdateGate(
        child: child ?? const SizedBox.shrink(),
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B57D0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
          ),
        ),
      ),
      home: ExpressLaunchGate(
        child: widget.startupError != null
            ? _MobileStartupError(error: widget.startupError!)
            : StreamBuilder<AuthState>(
                stream: supabase.auth.onAuthStateChange,
                builder: (context, snapshot) {
                  if (supabase.auth.currentSession == null) {
                    return const ExpressAuthPage();
                  }
                  return ConnectedAppShell(onExit: _logout);
                },
              ),
      ),
    );
  }
}

class _MobileStartupError extends StatelessWidget {
  final Object error;

  const _MobileStartupError({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 54),
                  const SizedBox(height: 14),
                  const Text(
                    'Express no pudo iniciar',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No se pudo conectar con el backend. Revisa tu conexión e inténtalo nuevamente.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF98A2B3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

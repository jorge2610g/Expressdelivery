import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_error_reporter.dart';
import 'auth_entry.dart';
import 'connected_shell.dart';
import 'core/supabase_client.dart';
import 'express_splash.dart';
import 'mobile_update_gate.dart';
import 'push_notifications.dart';
import 'preview_tools.dart';

// Signed Android entry point for Express. Administrative UI lives only in Adminexpress.

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppErrorReporter.configure(previewMode: false);

    Object? startupError;
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
      );
      await initializePushPlatform(
        packageName: 'com.express.usuario',
      );
    } catch (e, stack) {
      startupError = e;
      await AppErrorReporter.capture(
        e,
        stack,
        source: 'mobile_startup',
        screen: 'startup',
        fatal: false,
      );
    }

    runApp(ExpressMobileApp(startupError: startupError));
  }, (error, stack) {
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'mobile_zone',
        screen: 'global',
        fatal: true,
      ),
    );
  });
}

class ExpressMobileApp extends StatefulWidget {
  final Object? startupError;
  final bool previewMode;

  const ExpressMobileApp({
    super.key,
    this.startupError,
    this.previewMode = false,
  });

  @override
  State<ExpressMobileApp> createState() => _ExpressMobileAppState();
}

class _ExpressMobileAppState extends State<ExpressMobileApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;
  bool _passwordRecoveryMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.startupError == null) {
      _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() => _passwordRecoveryMode = true);
        } else if (state.event == AuthChangeEvent.signedOut) {
          setState(() => _passwordRecoveryMode = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _finishPasswordRecovery() {
    if (mounted) {
      setState(() => _passwordRecoveryMode = false);
    }
  }

  Future<void> _logout() async {
    if (supabase.auth.currentSession != null) {
      await supabase.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: widget.previewMode ? 'Express Preview' : 'Express',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (widget.previewMode) {
          return ExpressPreviewOverlay(
            navigatorKey: _navigatorKey,
            child: content,
          );
        }
        return AndroidReleaseUpdateGate(child: content);
      },
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
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B57D0),
          brightness: Brightness.dark,
          surface: const Color(0xFF141414),
        ),
        scaffoldBackgroundColor: const Color(0xFF101114),
        canvasColor: const Color(0xFF141414),
        cardColor: const Color(0xFF1B1B1B),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141414),
          foregroundColor: Colors.white,
          surfaceTintColor: Color(0xFF141414),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF343434)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF343434)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFF0B57D0),
              width: 1.5,
            ),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: ExpressLaunchGate(
        child: widget.startupError != null
            ? _MobileStartupError(error: widget.startupError!)
            : StreamBuilder<AuthState>(
                stream: supabase.auth.onAuthStateChange,
                builder: (context, snapshot) {
                  if (snapshot.data?.event == AuthChangeEvent.passwordRecovery ||
                      _passwordRecoveryMode) {
                    return ExpressPasswordRecoveryPage(
                      onDone: _finishPasswordRecovery,
                    );
                  }
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

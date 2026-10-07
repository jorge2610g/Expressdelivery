import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:terminate_restart/terminate_restart.dart';

import 'app_error_reporter.dart';
import 'auth_entry.dart';
import 'connected_shell.dart';
import 'core/express_supabase_bootstrap.dart';
import 'core/runtime_access.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'express_motion.dart';
import 'express_splash.dart';
import 'mobile_update_gate.dart';
import 'map_provider.dart';
import 'passenger_ads.dart';
import 'push_notifications.dart';
import 'preview_tools.dart';
import 'private_voice_call.dart';
import 'startup_permission_gate.dart';

// Signed Android entry point for Express. Administrative UI lives only in Adminexpress.

final GlobalKey<NavigatorState> expressNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> initializeExpressOptionalMobileServices({
  required String packageName,
}) async {
  // Voice calling is session-scoped and initializes through syncForSession()
  // only after auth exists. Keep startup free of parallel ZEGOCLOUD setup.
  try {
    await initializePushPlatform(packageName: packageName);
  } catch (error, stack) {
    debugPrint('Express optional push bootstrap failed: $error');
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'push_platform_startup',
        screen: 'startup',
        fatal: false,
      ),
    );
  }

  try {
    await ExpressPassengerAds.initialize();
  } catch (error, stack) {
    debugPrint('Express optional ads bootstrap failed: $error');
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'passenger_ads_startup',
        screen: 'startup',
        fatal: false,
      ),
    );
  }
}

Future<void> _syncPrivateVoiceCallSafely() async {
  try {
    await ExpressPrivateVoiceCall.instance.syncForSession();
  } catch (error, stack) {
    debugPrint('Express private voice session sync failed: $error');
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'private_voice_session_sync',
        screen: 'global',
        fatal: false,
      ),
    );
  }
}

const bool _compiledPreviewMode = bool.fromEnvironment(
  'EXPRESS_PREVIEW_MODE',
  defaultValue: false,
);

const String _compiledPackageName = String.fromEnvironment(
  'EXPRESS_FIREBASE_PACKAGE_NAME',
  defaultValue: 'com.express.usuario1',
);

void main() {
  runExpressMobile(
    previewMode: _compiledPreviewMode,
    packageName: _compiledPackageName,
  );
}

/// Single Android startup path for both Preview and Production.
///
/// The application code is identical. Only explicit build configuration
/// changes: runtime channel/package/Firebase plus Preview-only QA tools.
void runExpressMobile({
  required bool previewMode,
  required String packageName,
}) {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    ExpressRuntimeChannel.configureCompiledMode(previewMode);
    await AppErrorReporter.configure(previewMode: previewMode);

    if (previewMode) {
      try {
        TerminateRestart.instance.initialize();
      } catch (error, stack) {
        debugPrint('Express Preview restart helper failed: $error');
        unawaited(
          AppErrorReporter.capture(
            error,
            stack,
            source: 'preview_restart_helper',
            screen: 'startup',
            fatal: false,
          ),
        );
      }
    }

    Object? startupError;
    try {
      await initializeExpressSupabase();
    } catch (error, stack) {
      startupError = error;
      debugPrint('Express Supabase bootstrap failed: $error');
      unawaited(
        AppErrorReporter.capture(
          error,
          stack,
          source: previewMode ? 'preview_startup' : 'mobile_startup',
          screen: 'startup',
          eventName: 'SUPABASE_BOOTSTRAP_FAILED',
          fatal: false,
        ),
      );
    }

    runApp(
      ExpressMobileApp(
        startupError: startupError,
        previewMode: previewMode,
      ),
    );

    if (startupError == null) {
      unawaited(
        initializeExpressOptionalMobileServices(
          packageName: packageName,
        ),
      );
    }
  }, (error, stack) {
    debugPrint('Express uncaught startup/runtime error: $error');
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: previewMode ? 'preview_zone' : 'mobile_zone',
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
  final GlobalKey<NavigatorState> _navigatorKey = expressNavigatorKey;
  StreamSubscription<AuthState>? _authSubscription;
  bool _passwordRecoveryMode = false;

  @override
  void initState() {
    super.initState();
    ExpressPrivateVoiceCall.instance.attachNavigator(_navigatorKey);
    if (widget.startupError == null) {
      unawaited(_syncPrivateVoiceCallSafely());
      _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
        unawaited(_syncPrivateVoiceCallSafely());
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() => _passwordRecoveryMode = true);
        } else if (state.event == AuthChangeEvent.signedOut) {
          ExpressRuntimeChannel.resetToCompiledMode();
          setState(() => _passwordRecoveryMode = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    unawaited(ExpressPrivateVoiceCall.instance.uninitialize());
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
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ExpressPageTransitionsBuilder(),
            TargetPlatform.iOS: ExpressPageTransitionsBuilder(),
            TargetPlatform.macOS: ExpressPageTransitionsBuilder(),
            TargetPlatform.windows: ExpressPageTransitionsBuilder(),
            TargetPlatform.linux: ExpressPageTransitionsBuilder(),
          },
        ),
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
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ExpressPageTransitionsBuilder(),
            TargetPlatform.iOS: ExpressPageTransitionsBuilder(),
            TargetPlatform.macOS: ExpressPageTransitionsBuilder(),
            TargetPlatform.windows: ExpressPageTransitionsBuilder(),
            TargetPlatform.linux: ExpressPageTransitionsBuilder(),
          },
        ),
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
            ? _MobileStartupError(
                error: widget.startupError!,
                showTechnicalDetails: widget.previewMode,
              )
            : StreamBuilder<AuthState>(
                stream: supabase.auth.onAuthStateChange,
                builder: (context, snapshot) {
                  if (snapshot.data?.event == AuthChangeEvent.passwordRecovery ||
                      _passwordRecoveryMode) {
                    return ExpressPasswordRecoveryPage(
                      onDone: _finishPasswordRecovery,
                    );
                  }
                  final session = supabase.auth.currentSession;
                  if (session == null) {
                    return const ExpressAuthPage();
                  }
                  return _RuntimeAccessGate(
                    key: ValueKey(
                      'runtime-' +
                          session.user.id +
                          '-' +
                          ExpressRuntimeChannel.name,
                    ),
                    onExit: _logout,
                    child: ExpressStartupPermissionGate(
                      child: ConnectedAppShell(onExit: _logout),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _RuntimeAccessGate extends StatefulWidget {
  final Widget child;
  final VoidCallback onExit;

  const _RuntimeAccessGate({
    super.key,
    required this.child,
    required this.onExit,
  });

  @override
  State<_RuntimeAccessGate> createState() => _RuntimeAccessGateState();
}

class _RuntimeAccessGateState extends State<_RuntimeAccessGate> {
  late Future<Map<String, dynamic>> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = _loadAccess();
  }

  Future<Map<String, dynamic>> _loadAccess() async {
    final access = await resolveExpressRuntimeAccess();
    if (access['allowed'] == true) {
      await ExpressMapProvider.initializeQuotaGuard();
    }
    return access;
  }

  void _retry() {
    setState(() => _accessFuture = _loadAccess());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ExpressSplashPage();
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sync_problem_rounded, size: 54),
                          const SizedBox(height: 14),
                          const Text(
                            'No pudimos validar tu sesión',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'No entraremos a la aplicación hasta confirmar que tu cuenta corresponde al entorno correcto.',
                            textAlign: TextAlign.center,
                          ),
                          if (ExpressRuntimeChannel.previewMode) ...[
                            const SizedBox(height: 10),
                            Text(
                              snapshot.error.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF98A2B3),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reintentar'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: widget.onExit,
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Cerrar sesión'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final access = snapshot.data ?? const <String, dynamic>{};
        if (access['allowed'] == true) {
          return widget.child;
        }

        final boundEnvironment = access['bound_environment']?.toString();
        final preview = ExpressRuntimeChannel.previewMode;
        final title = preview
            ? 'Cuenta vinculada a Producción'
            : 'Cuenta vinculada a Preview';
        final message = preview
            ? boundEnvironment == 'production'
                ? 'Esta cuenta ya pertenece a Producción. Para probar Express Preview usa otra cuenta Google destinada a pruebas.'
                : 'Esta cuenta todavía no está habilitada para Express Preview.'
            : boundEnvironment == 'preview'
                ? 'Esta cuenta está reservada para Express Preview y no puede usar datos de Producción.'
                : 'No pudimos confirmar el entorno de esta cuenta.';

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          preview
                              ? Icons.science_outlined
                              : Icons.verified_user_outlined,
                          size: 58,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(height: 1.45),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: widget.onExit,
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Cerrar sesión'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileStartupError extends StatelessWidget {
  final Object error;
  final bool showTechnicalDetails;

  const _MobileStartupError({
    required this.error,
    required this.showTechnicalDetails,
  });

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
                  Text(
                    showTechnicalDetails
                        ? 'No se pudo completar el inicio de Express. Código: E-START-AUTH. Revisa los detalles de QA.'
                        : 'No se pudo completar el inicio de Express. Cierra y abre la aplicación nuevamente. Código: E-START-AUTH.',
                    textAlign: TextAlign.center,
                  ),
                  if (showTechnicalDetails) ...[
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

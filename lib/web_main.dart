import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_update_banner.dart';
import 'auth_entry.dart';
import 'connected_shell.dart';
import 'account_memory_reset.dart';
import 'core/account_device_cache.dart';
import 'core/runtime_access.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'express_motion.dart';
import 'push_notifications.dart';
import 'public_trip_share_page.dart';
import 'startup_permission_gate.dart';
import 'express_splash.dart';

const expressPackageVersion = String.fromEnvironment(
  'EXPRESS_PACKAGE_VERSION',
  defaultValue: 'dev',
);
const expressWebVersion = String.fromEnvironment(
  'EXPRESS_DISPLAY_VERSION',
  defaultValue: 'Express web',
);

String? expressTripShareTokenFromUri(Uri uri) {
  final raw = uri.queryParameters['trip_share']?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (raw.length != 64) return null;
  if (raw.replaceAll(RegExp(r'[0-9a-fA-F]'), '').isNotEmpty) return null;
  return raw.toLowerCase();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final initialUri = Uri.base;
  final initialFragment = initialUri.fragment.toLowerCase();
  final initialQuery = initialUri.query.toLowerCase();
  final initialPasswordRecovery =
      initialFragment.contains('type=recovery') ||
      initialQuery.contains('type=recovery');

  final initialTripShareToken = expressTripShareTokenFromUri(initialUri);

  Object? startupError;
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  } catch (e) {
    startupError = e;
  }

  if (startupError == null) {
    // Sesión restaurada desde el almacenamiento del navegador: si pertenece a
    // otra cuenta que la última usada, la caché anterior se borra antes de
    // pintar la primera pantalla.
    try {
      await switchAccountDeviceCachesIfNeeded(
        supabase.auth.currentUser?.id,
        clearMemory: forgetAccountMemory,
      );
    } catch (error) {
      debugPrint('Express account cache switch failed: $error');
    }
  }

  runApp(
    ExpressWebApp(
      startupError: startupError,
      initialPasswordRecovery: initialPasswordRecovery,
      initialTripShareToken: initialTripShareToken,
    ),
  );
}

class ExpressWebApp extends StatefulWidget {
  final Object? startupError;
  final bool initialPasswordRecovery;
  final String? initialTripShareToken;

  const ExpressWebApp({
    super.key,
    this.startupError,
    this.initialPasswordRecovery = false,
    this.initialTripShareToken,
  });

  @override
  State<ExpressWebApp> createState() => _ExpressWebAppState();
}

class _ExpressWebAppState extends State<ExpressWebApp> {
  StreamSubscription<AuthState>? _authSubscription;
  late bool _passwordRecoveryMode;

  static bool _uriIndicatesPasswordRecovery() {
    final uri = Uri.base;
    final fragment = uri.fragment.toLowerCase();
    final query = uri.query.toLowerCase();
    return fragment.contains('type=recovery') || query.contains('type=recovery');
  }

  @override
  void initState() {
    super.initState();
    _passwordRecoveryMode =
        widget.initialPasswordRecovery || _uriIndicatesPasswordRecovery();

    if (widget.startupError == null) {
      _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() => _passwordRecoveryMode = true);
        } else if (state.event == AuthChangeEvent.signedOut) {
          unawaited(clearAccountDeviceCaches(clearMemory: forgetAccountMemory));
          setState(() => _passwordRecoveryMode = false);
        } else if (state.event == AuthChangeEvent.signedIn) {
          unawaited(switchAccountDeviceCachesIfNeeded(
            state.session?.user.id,
            clearMemory: forgetAccountMemory,
          ));
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

  Future<void> _exitExperience() async {
    if (widget.startupError != null) return;
    final session = supabase.auth.currentSession;
    if (session != null) {
      await disablePushNotifications(session.accessToken);
      await supabase.auth.signOut();
    }
    ExpressRuntimeChannel.resetToCompiledMode();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Express · Viajes',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B57D0)),
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
      builder: (context, child) {
        return Stack(
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: AppUpdateBanner(
                currentPackageVersion: expressPackageVersion,
                currentDisplayVersion: expressWebVersion,
              ),
            ),
          ],
        );
      },
      home: ExpressLaunchGate(
        child: widget.startupError != null
            ? _StartupErrorPage(error: widget.startupError!)
            : widget.initialTripShareToken != null
                ? PublicTripSharePage(token: widget.initialTripShareToken!)
                : StreamBuilder<AuthState>(
                    stream: supabase.auth.onAuthStateChange,
                    builder: (context, snapshot) {
                      if (snapshot.data?.event ==
                              AuthChangeEvent.passwordRecovery ||
                          _passwordRecoveryMode ||
                          _uriIndicatesPasswordRecovery()) {
                        return ExpressPasswordRecoveryPage(
                          onDone: _finishPasswordRecovery,
                        );
                      }
                      final authenticated =
                          supabase.auth.currentSession != null;
                      if (!authenticated) {
                        return const ExpressAuthPage();
                      }
                      return _WebRuntimeAccessGate(
                        key: ValueKey(supabase.auth.currentUser?.id ?? ''),
                        onExit: _exitExperience,
                        child: ExpressStartupPermissionGate(
                          child: ConnectedAppShell(onExit: _exitExperience),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  final Object error;
  const _StartupErrorPage({required this.error});

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
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'La interfaz cargó, pero no se pudo conectar con el backend. Recarga la página. Si vuelve a ocurrir, revisaremos la conexión de Supabase.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF667085), height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
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

/// Resuelve el canal de la cuenta antes de montar la app. Al recargar la web
/// con sesión iniciada, el canal no se calculaba y quedaba en Producción.
class _WebRuntimeAccessGate extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onExit;

  const _WebRuntimeAccessGate({
    super.key,
    required this.child,
    required this.onExit,
  });

  @override
  State<_WebRuntimeAccessGate> createState() => _WebRuntimeAccessGateState();
}

class _WebRuntimeAccessGateState extends State<_WebRuntimeAccessGate> {
  late Future<Map<String, dynamic>> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = resolveExpressRuntimeAccess();
  }

  void _retry() {
    setState(() => _accessFuture = resolveExpressRuntimeAccess());
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
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No pudimos validar tu sesión',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Revisa tu conexión e inténtalo de nuevo.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _retry, child: const Text('Reintentar')),
                  ],
                ),
              ),
            ),
          );
        }
        final allowed = snapshot.data?['allowed'] == true;
        if (!allowed) {
          // Cuenta sin acceso a este entorno: cerrar sesión y volver al acceso.
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await supabase.auth.signOut();
            ExpressRuntimeChannel.resetToCompiledMode();
          });
          return const ExpressSplashPage();
        }
        return widget.child;
      },
    );
  }
}


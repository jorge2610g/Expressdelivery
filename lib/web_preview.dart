import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_update_banner.dart';
import 'auth_entry.dart';
import 'connected_shell.dart';
import 'core/supabase_client.dart';
import 'push_notifications.dart';
import 'express_splash.dart';

const expressPackageVersion = '1.5.46+87';
const expressWebVersion = 'Express v1.5.46 · build 87';

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

  runApp(ExpressWebApp(startupError: startupError));
}

class ExpressWebApp extends StatefulWidget {
  final Object? startupError;
  const ExpressWebApp({super.key, this.startupError});

  @override
  State<ExpressWebApp> createState() => _ExpressWebAppState();
}

class _ExpressWebAppState extends State<ExpressWebApp> {
  Future<void> _exitExperience() async {
    if (widget.startupError != null) return;
    final session = supabase.auth.currentSession;
    if (session != null) {
      await disablePushNotifications(session.accessToken);
      await supabase.auth.signOut();
    }
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
            const Positioned(
              right: 6,
              bottom: 6,
              child: SafeArea(
                top: false,
                left: false,
                child: IgnorePointer(child: _VersionBadge()),
              ),
            ),
          ],
        );
      },
      home: ExpressLaunchGate(
        child: widget.startupError != null
            ? _StartupErrorPage(error: widget.startupError!)
            : StreamBuilder<AuthState>(
                stream: supabase.auth.onAuthStateChange,
                builder: (context, snapshot) {
                  final authenticated = supabase.auth.currentSession != null;
                  if (!authenticated) {
                    return const ExpressAuthPage();
                  }
                  return ConnectedAppShell(onExit: _exitExperience);
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

class _VersionBadge extends StatelessWidget {
  const _VersionBadge();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x990F172A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x22FFFFFF)),
          boxShadow: const [],
        ),
        child: const Text(
          expressWebVersion,
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: .1,
          ),
        ),
      ),
    );
  }
}

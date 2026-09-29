import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_entry.dart';
import 'connected_shell.dart';
import 'core/supabase_client.dart';

const expressWebVersion = 'Express v1.2.3 · build 18';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(const ExpressWebApp());
}

class ExpressWebApp extends StatefulWidget {
  const ExpressWebApp({super.key});

  @override
  State<ExpressWebApp> createState() => _ExpressWebAppState();
}

class _ExpressWebAppState extends State<ExpressWebApp> {
  Future<void> _exitExperience() async {
    if (supabase.auth.currentSession != null) {
      await supabase.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Express · Viajes + Delivery',
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
      builder: (context, child) {
        return Stack(
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            const Positioned(
              right: 10,
              bottom: 10,
              child: SafeArea(
                top: false,
                left: false,
                child: IgnorePointer(child: _VersionBadge()),
              ),
            ),
          ],
        );
      },
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final authenticated = supabase.auth.currentSession != null;
          if (authenticated) {
            return ConnectedAppShell(onExit: _exitExperience);
          }
          return const ExpressAuthPage();
        },
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xD90F172A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x22FFFFFF)),
          boxShadow: const [
            BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: const Text(
          expressWebVersion,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
          ),
        ),
      ),
    );
  }
}

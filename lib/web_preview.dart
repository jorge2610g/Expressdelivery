import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';
import 'express_experience_preview.dart';
import 'login_preview.dart';
import 'ride_flow_preview.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(const ExpressWebPreview());
}

class ExpressWebPreview extends StatefulWidget {
  const ExpressWebPreview({super.key});

  @override
  State<ExpressWebPreview> createState() => _ExpressWebPreviewState();
}

class _ExpressWebPreviewState extends State<ExpressWebPreview> {
  bool demoMode = false;
  bool ridePreviewMode = false;

  Future<void> _exitExperience() async {
    if (supabase.auth.currentSession != null) {
      await supabase.auth.signOut();
      return;
    }
    if (mounted) {
      setState(() {
        demoMode = false;
        ridePreviewMode = false;
      });
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
      ),
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final authenticated = supabase.auth.currentSession != null;

          if (ridePreviewMode) {
            return RideFlowPreviewPage(
              onClose: () => setState(() => ridePreviewMode = false),
            );
          }

          if (demoMode || authenticated) {
            return ExpressExperiencePreview(onExit: _exitExperience);
          }

          return Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(child: ExpressLoginPreviewApp()),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 22,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => setState(() => demoMode = true),
                                icon: const Icon(Icons.play_circle_outline_rounded),
                                label: const Text('Entrar como demo'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => ridePreviewMode = true),
                                icon: const Icon(Icons.local_taxi_rounded),
                                label: const Text('Ver preview de Viajes'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

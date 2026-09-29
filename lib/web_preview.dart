import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connected_shell.dart';
import 'core/supabase_client.dart';
import 'delivery_flow_preview.dart';
import 'express_experience_preview.dart';
import 'login_preview.dart';
import 'ride_flow_preview.dart';

const expressWebVersion = 'Express v1.2.2 · build 17';

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
  bool deliveryPreviewMode = false;

  Future<void> _exitExperience() async {
    if (supabase.auth.currentSession != null) {
      await supabase.auth.signOut();
      return;
    }
    if (mounted) {
      setState(() {
        demoMode = false;
        ridePreviewMode = false;
        deliveryPreviewMode = false;
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

          if (ridePreviewMode) {
            return RideFlowPreviewPage(
              onClose: () => setState(() => ridePreviewMode = false),
            );
          }

          if (deliveryPreviewMode) {
            return DeliveryFlowPreviewPage(
              onClose: () => setState(() => deliveryPreviewMode = false),
            );
          }

          if (authenticated) {
            return ConnectedAppShell(onExit: _exitExperience);
          }

          if (demoMode) {
            return ExpressExperiencePreview(onExit: _exitExperience);
          }

          return Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(child: ExpressLoginPreviewApp()),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 44,
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
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => deliveryPreviewMode = true),
                                icon: const Icon(Icons.local_shipping_rounded),
                                label: const Text('Ver preview de Delivery'),
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
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
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

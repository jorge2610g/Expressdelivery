import 'package:flutter/material.dart';

import 'connected_experience.dart';
import 'express_splash.dart';
import 'services/express_service.dart';

class ConnectedAppShell extends StatefulWidget {
  final VoidCallback onExit;
  const ConnectedAppShell({super.key, required this.onExit});

  @override
  State<ConnectedAppShell> createState() => _ConnectedAppShellState();
}

class _ConnectedAppShellState extends State<ConnectedAppShell> {
  final service = ExpressService();
  int refresh = 0;
  late Future<Map<String, dynamic>?> bootstrapFuture;
  Map<String, dynamic>? initialPassengerState;

  @override
  void initState() {
    super.initState();
    bootstrapFuture = _bootstrap();
  }

  Future<Map<String, dynamic>?> _bootstrap() async {
    final started = DateTime.now();
    final account = await service.myUser();

    if (account != null &&
        account['account_status']?.toString() == 'active' &&
        account['active_mode']?.toString() != 'driver') {
      try {
        initialPassengerState = await service.preloadPassengerHomeState();
      } catch (_) {
        initialPassengerState = null;
        // PassengerMapHome will retry normally if startup preloading fails.
      }
    } else {
      initialPassengerState = null;
    }

    final elapsed = DateTime.now().difference(started);
    const minimumSplash = Duration(milliseconds: 1350);
    if (elapsed < minimumSplash) {
      await Future.delayed(minimumSplash - elapsed);
    }
    return account;
  }

  void _retryBootstrap() {
    setState(() {
      refresh++;
      bootstrapFuture = _bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey('account-' + refresh.toString()),
      future: bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ExpressSplashPage();
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sync_problem_rounded, size: 52),
                        const SizedBox(height: 14),
                        const Text(
                          'No pudimos cargar tu perfil',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Tu sesión está abierta, pero la aplicación no pudo leer el perfil. Puedes reintentar sin cerrar sesión.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF667085),
                            height: 1.45,
                          ),
                        ),
                        if (snapshot.hasError) ...[
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
                            onPressed: _retryBootstrap,
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
          );
        }

        final status = snapshot.data!['account_status']?.toString() ?? 'active';
        if (status != 'active') {
          return Scaffold(
            body: Center(
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
                          status == 'blocked'
                              ? Icons.block_rounded
                              : Icons.pause_circle_outline_rounded,
                          size: 56,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          status == 'blocked'
                              ? 'Cuenta bloqueada'
                              : 'Cuenta suspendida',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Tu cuenta no puede usar viajes, delivery, chat ni pagos en este momento. Contacta al administrador de Express.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF667085),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
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
          );
        }

        return ConnectedExperience(
          onExit: widget.onExit,
          initialMode:
              snapshot.data!['active_mode']?.toString() ?? 'passenger',
          initialPassengerState: initialPassengerState,
        );
      },
    );
  }
}

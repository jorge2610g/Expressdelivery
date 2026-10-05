import 'package:flutter/material.dart';

import 'connected_experience.dart';
import 'core/runtime_channel.dart';
import 'express_splash.dart';
import 'phone_verification_page.dart';
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
  bool bootstrapPhoneVerificationEnabled = false;
  bool phoneVerificationOpening = false;

  @override
  void initState() {
    super.initState();
    bootstrapFuture = _bootstrap();
  }

  Future<Map<String, dynamic>?> _bootstrap() async {
    final started = DateTime.now();
    final account = await service.myUser();

    if (account != null) {
      final activeMode =
          account['active_mode']?.toString() == 'driver'
              ? 'driver'
              : 'passenger';
      try {
        bootstrapPhoneVerificationEnabled =
            await service.phoneVerificationEnabledForMode(
          activeMode,
          forceRefresh: true,
        );
      } catch (_) {
        // Fail closed when configuration says verification is effective.
        // Production only becomes effective after a real provider proof.
        try {
          final settings = await service.appSettings(forceRefresh: true);
          final requested = activeMode == 'driver'
              ? settings['sms_verification_driver_enabled'] == true
              : settings['sms_verification_passenger_enabled'] == true;
          final providerReady = settings['sms_provider_verified_at'] != null;
          bootstrapPhoneVerificationEnabled =
              ExpressRuntimeChannel.previewMode
                  ? requested
                  : requested && providerReady;
        } catch (_) {
          bootstrapPhoneVerificationEnabled =
              ExpressRuntimeChannel.previewMode;
        }
      }
    } else {
      bootstrapPhoneVerificationEnabled = false;
    }

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
                        if (snapshot.hasError &&
                            ExpressRuntimeChannel.previewMode) ...[
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
                          'Tu cuenta no puede usar viajes, delivery, chat ni pagos en este momento. Contacta a soporte de Express.',
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

        final activeMode =
            snapshot.data!['active_mode']?.toString() ?? 'passenger';
        final phoneVerified =
            snapshot.data!['phone_verified_at'] != null;
        if (bootstrapPhoneVerificationEnabled && !phoneVerified) {
          final storedPhone = snapshot.data!['phone']?.toString();
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.phone_android_rounded,
                            size: 58,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Verifica tu teléfono',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            storedPhone == null || storedPhone.trim().isEmpty
                                ? 'Agrega un número con código de país y confírmalo por SMS.'
                                : 'Tu número ' +
                                    storedPhone +
                                    ' todavía no está verificado. Puedes verificarlo o cambiarlo.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: phoneVerificationOpening
                                  ? null
                                  : () async {
                                      setState(
                                        () => phoneVerificationOpening = true,
                                      );
                                      final verified =
                                          await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              PhoneVerificationPage(
                                            service: service,
                                            initialPhone: storedPhone,
                                            driver: activeMode == 'driver',
                                          ),
                                        ),
                                      );
                                      if (!mounted) return;
                                      setState(
                                        () => phoneVerificationOpening = false,
                                      );
                                      if (verified == true) {
                                        _retryBootstrap();
                                      }
                                    },
                              icon: const Icon(Icons.verified_outlined),
                              label: const Text(
                                'Verificar o cambiar número',
                              ),
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

        return ConnectedExperience(
          onExit: widget.onExit,
          initialMode: activeMode,
          initialPassengerState: initialPassengerState,
        );
      },
    );
  }
}

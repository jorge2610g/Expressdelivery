import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'core/supabase_client.dart';
import 'express_splash.dart';
import 'location_service.dart';
import 'push_notifications.dart';

/// Blocks entry into the authenticated Express experience until the critical
/// startup permissions have been requested.
///
/// Only permissions required by the core transport experience are requested
/// here:
/// - foreground location, so Express can resolve zone/currency/fares/pickup;
/// - notifications, so trip/offer/cancellation updates can reach the user.
///
/// Camera, microphone and media permissions remain feature-scoped and are
/// requested only when the user opens the corresponding feature.
class ExpressStartupPermissionGate extends StatefulWidget {
  final Widget child;

  const ExpressStartupPermissionGate({
    super.key,
    required this.child,
  });

  @override
  State<ExpressStartupPermissionGate> createState() =>
      _ExpressStartupPermissionGateState();
}

class _ExpressStartupPermissionGateState
    extends State<ExpressStartupPermissionGate>
    with WidgetsBindingObserver {
  bool _running = false;
  bool _ready = false;
  bool _introShown = false;
  bool _locationReady = false;
  bool _notificationsReady = false;
  bool _continueWithoutNotifications = false;
  bool _locationServiceDisabled = false;
  bool _locationPermissionBlocked = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepare());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_ready && !_running) {
      unawaited(_prepare(showIntro: false));
    }
  }

  Future<bool> _showIntroIfNeeded({
    required bool locationMissing,
    required bool notificationsMissing,
  }) async {
    if (_introShown || (!locationMissing && !notificationsMissing)) {
      return true;
    }
    _introShown = true;
    if (!mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_user_outlined),
        title: const Text('Permisos esenciales para Express'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (locationMissing)
              const _PermissionReason(
                icon: Icons.location_on_outlined,
                title: 'Ubicación',
                text:
                    'Para detectar tu ciudad, moneda, tarifas, punto de recogida y servicios disponibles.',
              ),
            if (locationMissing && notificationsMissing)
              const SizedBox(height: 14),
            if (notificationsMissing)
              const _PermissionReason(
                icon: Icons.notifications_active_outlined,
                title: 'Notificaciones',
                text:
                    'Para avisarte de solicitudes, ofertas, cambios, cancelaciones y novedades de un viaje.',
              ),
            const SizedBox(height: 14),
            const Text(
              'Express no usa estos permisos para publicidad. Cámara, micrófono y fotos se pedirán solo cuando uses una función que los necesite.',
              style: TextStyle(height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    return accepted == true;
  }

  Future<void> _prepare({bool showIntro = true}) async {
    if (_running || _ready) return;

    // Web has its own permission lifecycle. Browser geolocation and web push
    // must be requested by browser/user interaction and must never block the
    // authenticated shell during startup.
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _locationReady = true;
        _notificationsReady = true;
        _ready = true;
        _running = false;
        _message = null;
      });
      return;
    }

    setState(() {
      _running = true;
      _message = null;
      _locationServiceDisabled = false;
      _locationPermissionBlocked = false;
    });

    try {
      var locationPermission = await Geolocator.checkPermission();
      final pushStateBefore = await pushPermissionState();
      final locationMissing = locationPermission == LocationPermission.denied ||
          locationPermission == LocationPermission.deniedForever;
      final notificationsMissing = pushStateBefore != 'granted' &&
          pushStateBefore != 'unsupported' &&
          !_continueWithoutNotifications;

      if (showIntro) {
        final accepted = await _showIntroIfNeeded(
          locationMissing: locationMissing,
          notificationsMissing: notificationsMissing,
        );
        if (!accepted) {
          if (!mounted) return;
          setState(() {
            _message =
                'Express necesita solicitar los permisos esenciales antes de entrar.';
            _running = false;
          });
          return;
        }
      }

      locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied) {
        locationPermission = await Geolocator.requestPermission();
      }

      if (locationPermission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locationPermissionBlocked = true;
          _message =
              'El permiso de ubicación está bloqueado. Habilítalo en la configuración de Express para continuar.';
          _running = false;
        });
        return;
      }

      if (locationPermission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _message =
              'Necesitamos permiso de ubicación para preparar Express antes de entrar.';
          _running = false;
        });
        return;
      }

      final locationService = const ExpressLocationService();
      final locationServiceEnabled =
          await Geolocator.isLocationServiceEnabled();

      Position? position;
      if (!locationServiceEnabled) {
        // GPS apagado/no disponible: Express puede iniciar únicamente si ya
        // existe una ubicación válida guardada del último uso.
        position = await locationService.fallbackPosition();
        if (position == null) {
          if (!mounted) return;
          setState(() {
            _locationServiceDisabled = true;
            _message =
                'Activa la ubicación del dispositivo una vez para que Express pueda detectar tu ciudad. Después podremos usar tu última ubicación como respaldo.';
            _running = false;
          });
          return;
        }
      } else {
        // A valid permission + enabled location service is enough to enter.
        // Reuse a local fix immediately and refine GPS in the background so a
        // first-ever account never gets stuck on the splash waiting for a fix.
        position = await locationService.cachedPosition(
          maxAge: ExpressLocationService.persistentFallbackMaxAge,
        );
        if (position == null) {
          unawaited(
            locationService.passivePosition().then((fresh) {
              if (fresh != null) {
                ExpressLocationService.primeStartupPosition(fresh);
              }
            }),
          );
        }
      }

      if (position != null) {
        ExpressLocationService.primeStartupPosition(position);
      }
      _locationReady = true;

      final accessToken = supabase.auth.currentSession?.accessToken;
      var pushState = await pushPermissionState();
      if (pushState != 'granted' &&
          pushState != 'unsupported' &&
          !_continueWithoutNotifications &&
          accessToken != null &&
          accessToken.isNotEmpty) {
        await enablePushNotifications(accessToken);
        pushState = await pushPermissionState();
      }

      _notificationsReady =
          pushState == 'granted' || pushState == 'unsupported';

      if (!_notificationsReady && !_continueWithoutNotifications) {
        if (!mounted) return;
        setState(() {
          _message =
              'Activa las notificaciones para recibir ofertas y cambios importantes del viaje.';
          _running = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _ready = _locationReady &&
            (_notificationsReady || _continueWithoutNotifications);
        _running = false;
        _message = null;
      });
    } catch (error) {
      if (!mounted) return;
      final value = error.toString();
      setState(() {
        _message = value
            .replaceFirst('Bad state: ', '')
            .replaceFirst('StateError: ', '')
            .trim();
        _running = false;
      });
    }
  }

  Future<void> _openSettings() async {
    if (_locationServiceDisabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  }

  void _continueWithoutNotificationsNow() {
    if (!_locationReady) return;
    setState(() {
      _continueWithoutNotifications = true;
      _ready = true;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;

    if (_message == null) {
      return const ExpressSplashPage();
    }

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ExpressSplashPage()),
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface.withValues(
                    alpha: .94,
                  ),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Card(
                      margin: const EdgeInsets.all(24),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _locationServiceDisabled ||
                                      _locationPermissionBlocked
                                  ? Icons.location_off_rounded
                                  : Icons.notifications_off_outlined,
                              size: 50,
                              color: const Color(0xFF0B57D0),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Completa los permisos de Express',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(height: 1.4),
                            ),
                            const SizedBox(height: 18),
                            if (_locationServiceDisabled ||
                                _locationPermissionBlocked)
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _openSettings,
                                  icon: const Icon(Icons.settings_rounded),
                                  label: Text(
                                    _locationServiceDisabled
                                        ? 'Activar ubicación'
                                        : 'Abrir configuración',
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _running
                                      ? null
                                      : () => unawaited(
                                            _prepare(showIntro: false),
                                          ),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Volver a intentar'),
                                ),
                              ),
                            if (_locationReady && !_notificationsReady) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _continueWithoutNotificationsNow,
                                child:
                                    const Text('Continuar sin notificaciones'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionReason extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _PermissionReason({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF0B57D0)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}

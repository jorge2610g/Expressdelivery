import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'express_splash.dart';
import 'location_service.dart';

const _startupPlatformTimeout = Duration(seconds: 8);
const _startupPermissionPromptTimeout = Duration(seconds: 30);

Future<T> _startupWait<T>(
  Future<T> operation,
  String message, {
  Duration timeout = _startupPlatformTimeout,
}) {
  return operation.timeout(
    timeout,
    onTimeout: () => throw TimeoutException(message, timeout),
  );
}

/// Blocks entry into the authenticated Express experience until the critical
/// startup permissions have been requested.
///
/// Foreground location is resolved before entering the transport experience so
/// Express can load the correct zone, currency, fares and pickup location.
/// Notifications are initialized by the visible connected experience and must
/// never hold the user on the startup splash.
///
/// Camera, microphone and media permissions remain feature-scoped and are
/// requested only when the user opens the corresponding feature.
class ExpressStartupPermissionGate extends StatefulWidget {
  final Widget child;
  final VoidCallback? onReady;

  const ExpressStartupPermissionGate({
    super.key,
    required this.child,
    this.onReady,
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
  bool _locationServiceDisabled = false;
  bool _locationPermissionBlocked = false;
  bool _readyCallbackSent = false;
  String? _message;

  void _notifyReady() {
    if (_readyCallbackSent) return;
    _readyCallbackSent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    });
  }

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
        _ready = true;
        _running = false;
        _message = null;
      });
      _notifyReady();
      return;
    }

    setState(() {
      _running = true;
      _message = null;
      _locationServiceDisabled = false;
      _locationPermissionBlocked = false;
    });

    try {
      // Ask for location before touching FCM/notification plugins. Those
      // native services are optional to the GPS prompt and must not delay it.
      var locationPermission = await _startupWait(
        Geolocator.checkPermission(),
        'No se pudo revisar el permiso de ubicación. Vuelve a intentarlo.',
      );
      final locationMissing =
          locationPermission == LocationPermission.denied ||
          locationPermission == LocationPermission.deniedForever;

      if (showIntro) {
        final accepted = await _showIntroIfNeeded(
          locationMissing: locationMissing,
          notificationsMissing: false,
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

      locationPermission = await _startupWait(
        Geolocator.checkPermission(),
        'No se pudo revisar el permiso de ubicación. Vuelve a intentarlo.',
      );
      if (locationPermission == LocationPermission.denied) {
        locationPermission = await _startupWait(
          Geolocator.requestPermission(),
          'La solicitud de ubicación no respondió. Vuelve a Express e inténtalo otra vez.',
          timeout: _startupPermissionPromptTimeout,
        );
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

      const locationService = ExpressLocationService();
      // A slow Android location service must not keep the user on the splash.
      // If its status channel times out, continue with the saved location (if
      // any) and let the map refresh GPS after the app is visible. A confirmed
      // disabled GPS still follows the explicit settings flow below.
      bool? locationServiceEnabled;
      try {
        locationServiceEnabled = await _startupWait(
          Geolocator.isLocationServiceEnabled(),
          'No se pudo comprobar el GPS.',
        );
      } on TimeoutException {
        locationServiceEnabled = null;
      }

      Position? position;
      if (locationServiceEnabled == false) {
        // GPS apagado/no disponible: Express puede iniciar únicamente si ya
        // existe una ubicación válida guardada del último uso.
        try {
          position = await _startupWait(
            locationService.fallbackPosition(),
            'La ubicación guardada tardó demasiado en cargarse.',
          );
        } on TimeoutException {
          position = null;
        }
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
        try {
          position = await _startupWait(
            locationService.cachedPosition(
              maxAge: ExpressLocationService.persistentFallbackMaxAge,
            ),
            'La ubicación guardada tardó demasiado en cargarse.',
          );
        } on TimeoutException {
          // Location platform channels can be delayed during Android startup.
          // Keep the app usable and let its visible map request a fresh fix.
          position = null;
        }
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
      if (!mounted) return;
      setState(() {
        _ready = true;
        _running = false;
        _message = null;
      });
      _notifyReady();
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
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .94),
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
                                  : Icons.location_searching_rounded,
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}

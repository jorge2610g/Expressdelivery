import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connected_experience.dart';
import 'core/runtime_channel.dart';
import 'express_splash.dart';
import 'location_service.dart';
import 'map_provider.dart';
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
  Map<String, dynamic>? initialPassengerLanding;
  double? initialPassengerLatitude;
  double? initialPassengerLongitude;
  bool bootstrapPhoneVerificationEnabled = false;
  bool phoneVerificationOpening = false;
  bool passengerLandingRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    bootstrapFuture = _bootstrap();
  }

  String get _accountBootstrapCacheKey =>
      'express_account_bootstrap_v1_' + service.userId;

  String get _passengerLandingCacheKey =>
      'express_passenger_landing_v1_' + service.userId;

  Future<void> _cacheAccountBootstrap(Map<String, dynamic> account) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _accountBootstrapCacheKey,
        jsonEncode(<String, dynamic>{
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'account': account,
        }),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _readCachedAccountBootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_accountBootstrapCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final savedAt =
          DateTime.tryParse(decoded['saved_at']?.toString() ?? '')?.toUtc();
      final account = decoded['account'];
      if (savedAt == null ||
          account is! Map ||
          DateTime.now().toUtc().difference(savedAt) >
              const Duration(days: 7)) {
        return null;
      }
      return Map<String, dynamic>.from(account);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cachePassengerLanding(
    Map<String, dynamic> landing,
    double latitude,
    double longitude,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _passengerLandingCacheKey,
        jsonEncode(<String, dynamic>{
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'latitude': latitude,
          'longitude': longitude,
          'landing': landing,
        }),
      );
    } catch (_) {
      // El cache local nunca debe bloquear el splash.
    }
  }

  Future<Map<String, dynamic>?> _readCachedPassengerLanding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_passengerLandingCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final savedAt =
          DateTime.tryParse(decoded['saved_at']?.toString() ?? '')?.toUtc();
      if (savedAt == null ||
          DateTime.now().toUtc().difference(savedAt) >
              const Duration(days: 30)) {
        return null;
      }

      final latitude = (decoded['latitude'] as num?)?.toDouble();
      final longitude = (decoded['longitude'] as num?)?.toDouble();
      final landing = decoded['landing'];
      if (latitude == null || longitude == null || landing is! Map) {
        return null;
      }

      initialPassengerLatitude = latitude;
      initialPassengerLongitude = longitude;
      return <String, dynamic>{
        ...Map<String, dynamic>.from(landing),
        '_local_cache': true,
        '_cache_saved_at': savedAt.toIso8601String(),
        '_cache_latitude': latitude,
        '_cache_longitude': longitude,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _offlinePassengerLanding() {
    return <String, dynamic>{
      'inside_coverage': true,
      'offline_cached': true,
      'location_pending': true,
      '_local_cache': true,
      'zone': <String, dynamic>{'name': 'Express'},
      'landing': <String, dynamic>{
        'mode': 'direct',
        'default_module': 'ride',
        'title': 'Express',
        'subtitle': 'Usando tu última ubicación guardada',
        'modules': const <Map<String, dynamic>>[
          <String, dynamic>{
            'module_key': 'ride',
            'name': 'Viajes',
            'enabled': true,
          },
        ],
      },
    };
  }

  Future<Map<String, dynamic>> _preparePassengerLanding() async {
    final locationService = const ExpressLocationService();
    final cachedLanding = await _readCachedPassengerLanding();
    final cachedLatitude = initialPassengerLatitude;
    final cachedLongitude = initialPassengerLongitude;
    final cachedSavedAt = DateTime.tryParse(
      cachedLanding?['_cache_saved_at']?.toString() ?? '',
    )?.toUtc();

    // Normal navigation is cache-first. A fresh local landing does not need a
    // GPS request nor another zone RPC just to redraw the same city/currency.
    if (cachedLanding != null &&
        cachedSavedAt != null &&
        DateTime.now().toUtc().difference(cachedSavedAt) <=
            ExpressLocationService.passiveCacheMaxAge) {
      return cachedLanding;
    }

    final position = await locationService.passivePosition();
    if (position == null) {
      return cachedLanding ?? _offlinePassengerLanding();
    }

    initialPassengerLatitude = position.latitude;
    initialPassengerLongitude = position.longitude;

    // If the user is still essentially in the same place, refresh only the
    // device cache. This avoids backend zone/currency calls on routine opens.
    if (cachedLanding != null &&
        cachedLatitude != null &&
        cachedLongitude != null) {
      final movedMeters = locationService.distanceMeters(
        fromLatitude: cachedLatitude,
        fromLongitude: cachedLongitude,
        toLatitude: position.latitude,
        toLongitude: position.longitude,
      );
      if (movedMeters < 750) {
        final stableLanding = Map<String, dynamic>.from(cachedLanding)
          ..removeWhere((key, _) => key.startsWith('_cache_') || key == '_local_cache');
        await _cachePassengerLanding(
          stableLanding,
          position.latitude,
          position.longitude,
        );
        return <String, dynamic>{
          ...stableLanding,
          '_local_cache': true,
          '_cache_saved_at': DateTime.now().toUtc().toIso8601String(),
          '_cache_latitude': position.latitude,
          '_cache_longitude': position.longitude,
        };
      }
    }

    try {
      final previous = await service
          .currentOperatingContext()
          .timeout(const Duration(seconds: 5));
      final detected = await service
          .zoneContext(
            latitude: position.latitude,
            longitude: position.longitude,
            audience: 'passenger',
            persistZone: false,
          )
          .timeout(const Duration(seconds: 8));

      var resolved = Map<String, dynamic>.from(detected);
      final zone = detected['zone'] is Map
          ? Map<String, dynamic>.from(detected['zone'] as Map)
          : <String, dynamic>{};
      final previousCountry =
          previous['country_code']?.toString().trim().toUpperCase() ?? '';
      final detectedCountry =
          zone['country_code']?.toString().trim().toUpperCase() ?? '';

      if (detected['inside_coverage'] == true &&
          detectedCountry.isNotEmpty) {
        if (previousCountry.isNotEmpty &&
            previousCountry != detectedCountry) {
          resolved = <String, dynamic>{
            ...resolved,
            'country_change_declined': true,
            'previous_context': previous,
          };
        } else {
          await service
              .setMyZoneFromLocation(
                latitude: position.latitude,
                longitude: position.longitude,
              )
              .timeout(const Duration(seconds: 5));
        }
      }

      await _cachePassengerLanding(
        resolved,
        position.latitude,
        position.longitude,
      );
      return <String, dynamic>{
        ...resolved,
        '_cache_saved_at': DateTime.now().toUtc().toIso8601String(),
        '_cache_latitude': position.latitude,
        '_cache_longitude': position.longitude,
      };
    } catch (_) {
      return cachedLanding ?? _offlinePassengerLanding();
    }
  }

  Future<void> _refreshPassengerLandingInBackground() async {
    if (passengerLandingRefreshInFlight) return;
    passengerLandingRefreshInFlight = true;
    try {
      final next = await _preparePassengerLanding();
      if (!mounted) return;
      setState(() => initialPassengerLanding = next);
    } finally {
      passengerLandingRefreshInFlight = false;
    }
  }

  Future<Map<String, dynamic>?> _bootstrap() async {
    final started = DateTime.now();

    Map<String, dynamic>? account;
    try {
      account = await service.myUser();
      if (account != null) {
        await _cacheAccountBootstrap(account);
      }
    } catch (_) {
      account = await _readCachedAccountBootstrap();
      if (account == null) rethrow;
    }

    if (account != null) {
      try {
        await ExpressMapProvider.initializeQuotaGuard();
      } catch (_) {
        // El mapa tiene fallback seguro; una falla de cuota no bloquea inicio.
      }

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
      // Never make the first authenticated frame wait for a live GPS fix.
      // Show the last local landing (or a neutral ride shell) immediately and
      // improve location/zone in the background.
      initialPassengerLanding =
          await _readCachedPassengerLanding() ?? _offlinePassengerLanding();
      unawaited(_refreshPassengerLandingInBackground());
      try {
        initialPassengerState = await service.preloadPassengerHomeState();
      } catch (_) {
        initialPassengerState = null;
        // PassengerMapHome continuará con el estado local/cacheado disponible.
      }
    } else {
      initialPassengerState = null;
      initialPassengerLanding = null;
      initialPassengerLatitude = null;
      initialPassengerLongitude = null;
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
          initialPassengerLanding: initialPassengerLanding,
          initialPassengerLatitude: initialPassengerLatitude,
          initialPassengerLongitude: initialPassengerLongitude,
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';
import 'driver_setup.dart';
import 'driver_subscription_page.dart';
import 'express_account_pages.dart';
import 'express_branding.dart';
import 'express_delivery_v2_page.dart';
import 'location_picker.dart';
import 'location_service.dart';
import 'location_permission_disclosure.dart';
import 'money_format.dart';
import 'phone_verification_page.dart';
import 'push_notifications.dart';
import 'services/express_service.dart';
import 'service_tracking.dart';
import 'video_style_home.dart';

const _blue = Color(0xFF0B57D0);
const _blueDark = Color(0xFF073B8C);
const _yellow = Color(0xFFFFC928);
const _bg = Color(0xFFF5F7FB);
const _muted = Color(0xFF667085);

bool _experienceDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _experienceSurface(BuildContext context) =>
    _experienceDark(context) ? const Color(0xFF17191D) : Colors.white;

Color _experienceSoftSurface(BuildContext context) =>
    _experienceDark(context)
        ? const Color(0xFF22252B)
        : const Color(0xFFF5F7FA);

Color _experienceMuted(BuildContext context) =>
    _experienceDark(context) ? const Color(0xFFB7BDC8) : _muted;

Color _experienceBorder(BuildContext context) =>
    _experienceDark(context)
        ? const Color(0xFF343840)
        : const Color(0xFFE4E9F0);

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _serviceMoney(Object? value, Object? currencyRaw) =>
    expressMoney(value, currencyRaw);

String _tripCurrency(Map<String, dynamic> trip) =>
    expressTripCurrency(trip);

Map<String, num> _sumMoneyByCurrency(
  Iterable<Map<String, dynamic>> rows,
  Object? Function(Map<String, dynamic>) amountOf,
  String Function(Map<String, dynamic>) currencyOf,
) {
  final totals = <String, num>{};
  for (final row in rows) {
    final amount = _asDouble(amountOf(row)) ?? 0;
    final currency = expressCurrencyCode(currencyOf(row));
    totals[currency] = (totals[currency] ?? 0) + amount;
  }
  return totals;
}

String _moneyTotalsLabel(
  Map<String, num> totals, {
  String fallbackCurrency = 'BOB',
}) {
  if (totals.isEmpty) return expressMoney(0, fallbackCurrency);
  final entries = totals.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => expressMoney(entry.value, entry.key)).join(' · ');
}


class ConnectedExperience extends StatefulWidget {
  final VoidCallback onExit;
  final String initialMode;
  final Map<String, dynamic>? initialPassengerState;

  const ConnectedExperience({
    super.key,
    required this.onExit,
    this.initialMode = 'passenger',
    this.initialPassengerState,
  });

  @override
  State<ConnectedExperience> createState() => _ConnectedExperienceState();
}

class _ConnectedExperienceState extends State<ConnectedExperience> {
  final service = ExpressService();
  bool loading = false;
  late String mode;
  String? error;
  StreamSubscription<ExpressPushEvent>? _pushSubscription;
  RealtimeChannel? _accountModeChannel;
  int _pushEpoch = 0;
  String? _lastOpenedPushKey;

  @override
  void initState() {
    super.initState();
    mode = widget.initialMode;
    _listenToPushEvents();
    _listenToAccountMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupPushNotifications();
      final pending = takePendingExpressPushEvent();
      if (pending != null) {
        unawaited(_handlePushEvent(pending));
      }
    });
  }

  void _listenToPushEvents() {
    _pushSubscription = expressPushEvents().listen((event) {
      unawaited(_handlePushEvent(event));
    });
  }

  void _listenToAccountMode() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    _accountModeChannel = supabase
        .channel('account-active-mode-' + uid)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (payload) {
            final next = payload.newRecord['active_mode']?.toString();
            if ((next != 'driver' && next != 'passenger') ||
                !mounted ||
                next == mode) {
              return;
            }
            // active_mode es estado de cuenta, no un rol duplicado por
            // dispositivo. Si otra sesión lo cambia, este dispositivo debe
            // reconstruir inmediatamente el shell correcto.
            setState(() {
              mode = next!;
              _pushEpoch++;
            });
          },
        )
        .subscribe();
  }

  Future<void> _handlePushEvent(ExpressPushEvent event) async {
    if (!event.opened) return;

    final key = <String?>[
      event.notificationId,
      event.type,
      event.rideRequestId,
      event.offerId,
    ].whereType<String>().join('|');
    if (key.isNotEmpty && key == _lastOpenedPushKey) return;
    _lastOpenedPushKey = key;

    String? targetMode = event.mode;
    if (targetMode != 'driver' && targetMode != 'passenger') {
      targetMode = null;
    }
    if (targetMode == null && event.type == 'ride_request') {
      targetMode = 'driver';
    } else if (targetMode == null &&
        const {'ride_offer', 'new_offer', 'ride_offer_received'}
            .contains(event.type)) {
      targetMode = 'passenger';
    }

    final resolvedMode = targetMode;
    var modeSwitchSucceeded = true;
    try {
      if (resolvedMode == 'driver') {
        final profile = await service.myDriverProfile(forceRefresh: true);
        if (profile?['approval_status']?.toString() != 'approved') {
          throw StateError('El perfil de conductor no está aprobado.');
        }
      }
      if (resolvedMode != null && resolvedMode != mode) {
        await service.setActiveMode(resolvedMode);
      }
    } catch (_) {
      modeSwitchSucceeded = false;
    }

    if (!mounted) return;
    setState(() {
      if (modeSwitchSucceeded && resolvedMode != null) {
        mode = resolvedMode;
      }
      // Reconstruir el shell fuerza una lectura fresca del viaje/oferta
      // asociado a la push que el usuario acaba de abrir.
      _pushEpoch++;
    });
  }

  @override
  void dispose() {
    _pushSubscription?.cancel();
    final accountModeChannel = _accountModeChannel;
    if (accountModeChannel != null) {
      unawaited(supabase.removeChannel(accountModeChannel));
    }
    super.dispose();
  }

  Future<void> _setupPushNotifications() async {
    final accessToken = supabase.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) return;

    final permission = await pushPermissionState();

    if (permission == 'denied' || permission == 'unsupported') {
      return;
    }

    // Un solo flujo: Android muestra su cuadro nativo cuando corresponde.
    // Si ya estaba permitido, esta llamada solo asegura el token FCM.
    await enablePushNotifications(accessToken);
  }

  Future<void> _load() async {
    try {
      final user = await service.myUser();
      if (!mounted) return;
      setState(() {
        mode = user?['active_mode']?.toString() ?? 'passenger';
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  bool _driverProfileComplete(
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>> vehicles,
  ) {
    if (profile == null) return false;
    final license = profile['license_number']?.toString().trim() ?? '';
    final activeVehicle = vehicles.any((vehicle) {
      if (vehicle['is_active'] != true) return false;
      return (vehicle['brand']?.toString().trim().isNotEmpty ?? false) &&
          (vehicle['model']?.toString().trim().isNotEmpty ?? false) &&
          (vehicle['plate']?.toString().trim().isNotEmpty ?? false);
    });
    return license.isNotEmpty && activeVehicle;
  }

  Future<bool> _prepareDriverMode() async {
    var profile = await service.myDriverProfile(forceRefresh: true);
    var vehicles = await service.myVehicles(forceRefresh: true);
    final approved = profile?['approval_status']?.toString() == 'approved';
    final complete = _driverProfileComplete(profile, vehicles);

    if (profile == null || !complete || !approved) {
      if (!mounted) return false;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverSetupPage(service: service),
        ),
      );
      if (!mounted) return false;

      profile = await service.myDriverProfile(forceRefresh: true);
      vehicles = await service.myVehicles(forceRefresh: true);

      if (!_driverProfileComplete(profile, vehicles)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Completa tus datos de conductor y vehículo para enviar la solicitud.',
            ),
          ),
        );
        return false;
      }

      if (profile?['approval_status']?.toString() != 'approved') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tu solicitud de conductor está en revisión. '
              'Mientras tanto puedes seguir usando Express como pasajero.',
            ),
          ),
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _switchMode(String value) async {
    try {
      if (value == 'driver') {
        final ready = await _prepareDriverMode();
        if (!ready) return;
      } else if (value == 'passenger') {
        // El backend apaga automáticamente al conductor al abandonar este modo.
        // Si existe un servicio activo, la transición se rechaza para no cortar
        // tracking, ofertas ni el flujo de viaje en curso.
        final profile = await service.myDriverProfile(forceRefresh: true);
        if (profile?['online_status']?.toString() == 'busy') {
          throw StateError(
            'Finaliza o cancela tu servicio activo antes de cambiar a Pasajero.',
          );
        }
      }

      final verificationEnabled =
          await service.phoneVerificationEnabledForMode(
        value,
        forceRefresh: true,
      );
      if (verificationEnabled) {
        final user = await service.myUser(forceRefresh: true);
        final verified = user?['phone_verified_at'] != null;
        if (!verified) {
          if (!mounted) return;
          final completed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => PhoneVerificationPage(
                service: service,
                initialPhone: user?['phone']?.toString(),
                driver: value == 'driver',
              ),
            ),
          );
          if (completed != true) return;
        }
      }

      await service.setActiveMode(value);
      if (!mounted) return;
      setState(() => mode = value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar de modo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final surface = dark ? const Color(0xFF17191D) : Colors.white;
    final background = dark ? const Color(0xFF0F1115) : _bg;
    final border =
        dark ? const Color(0xFF343840) : const Color(0xFFD9E0EA);
    final scheme = ColorScheme.fromSeed(
      seedColor: _blue,
      brightness: brightness,
    );

    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      cardColor: surface,
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? const Color(0xFF22252B) : const Color(0xFFF5F7FA),
        selectedColor: dark ? const Color(0xFF17315E) : const Color(0xFFEAF2FF),
        disabledColor: dark ? const Color(0xFF1B1D22) : const Color(0xFFF2F4F7),
        side: BorderSide(color: border),
        labelStyle: TextStyle(
          color: dark ? const Color(0xFFF5F7FA) : const Color(0xFF101828),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: dark ? Colors.white : const Color(0xFF101828),
        surfaceTintColor: surface,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: _blue.withValues(alpha: dark ? .28 : .14),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? (dark ? const Color(0xFF7EB3FF) : _blue)
                : (dark
                    ? const Color(0xFFB7BDC8)
                    : const Color(0xFF667085)),
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected
                ? (dark ? const Color(0xFF9BC3FF) : _blue)
                : (dark
                    ? const Color(0xFFB7BDC8)
                    : const Color(0xFF475467)),
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            fontSize: 12,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: TextStyle(
          color: dark ? const Color(0xFFB7BDC8) : const Color(0xFF475467),
        ),
        hintStyle: TextStyle(
          color: dark ? const Color(0xFF8F98A6) : const Color(0xFF667085),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
      ),
    );

    if (loading) {
      return Theme(
        data: theme,
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (error != null) {
      return Theme(
        data: theme,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 50),
                  const SizedBox(height: 12),
                  const Text('No se pudo cargar tu cuenta.'),
                  const SizedBox(height: 8),
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('Reintentar')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Theme(
      data: theme,
      child: mode == 'driver'
          ? _DriverShell(
              key: ValueKey('driver-push-$_pushEpoch'),
              service: service,
              onSwitchMode: () => _switchMode('passenger'),
              onExit: widget.onExit,
            )
          : _CustomerShell(
              key: ValueKey('passenger-push-$_pushEpoch'),
              service: service,
              onSwitchMode: () => _switchMode('driver'),
              onExit: widget.onExit,
              initialPassengerState: widget.initialPassengerState,
            ),
    );
  }
}

class _CustomerShell extends StatefulWidget {
  final ExpressService service;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;
  final Map<String, dynamic>? initialPassengerState;

  const _CustomerShell({
    super.key,
    required this.service,
    required this.onSwitchMode,
    required this.onExit,
    this.initialPassengerState,
  });

  @override
  State<_CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<_CustomerShell> {
  int index = 0;
  int revision = 0;
  int passengerHomeEpoch = 0;
  bool passengerFlowActive = false;
  String? selectedHomeModule;
  double? passengerLandingLatitude;
  double? passengerLandingLongitude;
  late Future<Map<String, dynamic>> passengerLandingFuture;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialPassengerState;
    if (initial?['active_delivery'] is Map) {
      selectedHomeModule = 'delivery';
    } else if (initial?['open_ride'] is Map ||
        initial?['active_trip'] is Map ||
        (initial?['offers'] is List &&
            (initial?['offers'] as List).isNotEmpty)) {
      selectedHomeModule = 'ride';
    }

    passengerLandingFuture = _loadPassengerLanding();
  }

  Future<Map<String, dynamic>> _loadPassengerLanding() async {
    try {
      final position =
          await const ExpressLocationService().currentPosition();
      passengerLandingLatitude = position.latitude;
      passengerLandingLongitude = position.longitude;
      return await widget.service.zoneContext(
        latitude: position.latitude,
        longitude: position.longitude,
        audience: 'passenger',
      );
    } catch (_) {
      return <String, dynamic>{
        'inside_coverage': false,
        'zone': null,
        'landing': <String, dynamic>{
          'mode': 'direct',
          'default_module': 'ride',
          'title': '¿Qué necesitas hoy?',
          'subtitle': 'Elige un servicio de Express',
          'modules': const <Map<String, dynamic>>[],
        },
      };
    }
  }

  void _reloadPassengerLanding() {
    setState(() {
      selectedHomeModule = null;
      passengerLandingFuture = _loadPassengerLanding();
    });
  }

  void refreshAll() => setState(() => revision++);

  void resetPassengerHome() {
    setState(() {
      revision++;
      passengerHomeEpoch++;
      index = 0;
    });
  }

  Widget _passengerModulePage(String module) {
    if (module == 'market') {
      passengerFlowActive = true;
      return ExpressDeliveryV2Page(
        service: widget.service,
        latitude: passengerLandingLatitude,
        longitude: passengerLandingLongitude,
        onOpenRide: () {
          if (!mounted) return;
          setState(() {
            index = 0;
            selectedHomeModule = 'ride';
            passengerFlowActive = false;
          });
        },
        onOpenDriver: widget.onSwitchMode,
        onOpenServices: () {
          if (!mounted) return;
          setState(() {
            index = 0;
            selectedHomeModule = null;
            passengerFlowActive = false;
          });
        },
      );
    }

    return PassengerMapHome(
      key: ValueKey(
        'passenger-home-' +
            passengerHomeEpoch.toString() +
            '-' +
            module,
      ),
      service: widget.service,
      initialState:
          passengerHomeEpoch == 0 ? widget.initialPassengerState : null,
      initialServiceType: module == 'delivery' ? 'delivery' : 'ride',
      onChanged: refreshAll,
      onHardReset: resetPassengerHome,
      onSwitchMode: widget.onSwitchMode,
      onOpenMarket: () {
        if (!mounted) return;
        setState(() {
          index = 0;
          selectedHomeModule = 'market';
          passengerFlowActive = true;
        });
      },
      onHistory: () => setState(() => index = 1),
      onPayments: () => setState(() => index = 2),
      onProfile: () => setState(() => index = 3),
      onFlowStateChanged: (active) {
        if (!mounted || passengerFlowActive == active) return;
        setState(() => passengerFlowActive = active);
      },
      onSavedPlaces: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _SavedAddressesPage(service: widget.service),
        ),
      ),
      onSafety: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _SafetyPage(service: widget.service),
        ),
      ),
    );
  }

  Widget _passengerEntryPage() {
    final selected = selectedHomeModule;
    if (selected != null) return _passengerModulePage(selected);

    return FutureBuilder<Map<String, dynamic>>(
      future: passengerLandingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final zone = data['zone'] is Map
            ? Map<String, dynamic>.from(data['zone'] as Map)
            : const <String, dynamic>{};
        final landing = data['landing'] is Map
            ? Map<String, dynamic>.from(data['landing'] as Map)
            : const <String, dynamic>{};
        final modules = landing['modules'] is List
            ? (landing['modules'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];

        final mode = landing['mode']?.toString() ?? 'direct';
        final defaultModule =
            landing['default_module']?.toString() ?? 'ride';
        final shouldShowLanding = mode == 'always' ||
            (mode == 'auto' && modules.length > 1);

        if (!shouldShowLanding) {
          var target = defaultModule;
          if (modules.isNotEmpty &&
              !modules.any(
                (row) => row['module_key']?.toString() == target,
              )) {
            target = modules.first['module_key']?.toString() ?? 'ride';
          }
          return _passengerModulePage(target);
        }

        if (modules.isEmpty) {
          return _passengerModulePage(defaultModule);
        }

        passengerFlowActive = false;
        return _PassengerLandingPage(
          zoneName: zone['name']?.toString() ??
              zone['city']?.toString() ??
              'Express',
          title: landing['title']?.toString() ?? '¿Qué necesitas hoy?',
          subtitle: landing['subtitle']?.toString() ??
              'Elige un servicio de Express',
          modules: modules,
          onRefresh: _reloadPassengerLanding,
          onSelect: (module) {
            setState(() {
              passengerFlowActive = false;
              selectedHomeModule = module;
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final navActive =
        dark ? const Color(0xFF9CC2FF) : const Color(0xFF0B57D0);
    final navInactive =
        dark ? const Color(0xFFB7BDC8) : const Color(0xFF667085);
    final navBackground =
        dark ? const Color(0xFF121212) : Colors.white;
    final navIndicator =
        dark ? const Color(0xFF17315E) : const Color(0xFFDDE8FF);

    final pages = [
      _passengerEntryPage(),
      ExpressHistoryPage(
        service: widget.service,
        driver: false,
      ),
      ExpressWalletPage(
        service: widget.service,
        driver: false,
      ),
      ExpressProfileHubPage(
        service: widget.service,
        driver: false,
        onSwitchMode: widget.onSwitchMode,
        onExit: widget.onExit,
        onSavedAddresses: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SavedAddressesPage(service: widget.service),
          ),
        ),
        onSafety: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SafetyPage(service: widget.service),
          ),
        ),
      ),
    ];

    return PopScope(
      canPop: selectedHomeModule == null && index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !mounted) return;
        setState(() {
          if (index != 0) {
            index = 0;
            return;
          }
          selectedHomeModule = null;
          passengerFlowActive = false;
        });
      },
      child: Scaffold(
        body: IndexedStack(index: index, children: pages),
        bottomNavigationBar:
            index == 0 &&
                    (passengerFlowActive || selectedHomeModule == 'market')
                ? null
                : NavigationBar(
              height: 72,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: index,
              onDestinationSelected: (value) {
                setState(() {
                  if (value == 0 && index == 0) {
                    selectedHomeModule = null;
                    passengerFlowActive = false;
                  }
                  index = value;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Inicio',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: 'Historial',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                  label: 'Pagos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Perfil',
                ),
              ],
            ),
      ),
    );
  }
}

class _PassengerLandingPage extends StatelessWidget {
  final String zoneName;
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> modules;
  final ValueChanged<String> onSelect;
  final VoidCallback onRefresh;

  const _PassengerLandingPage({
    required this.zoneName,
    required this.title,
    required this.subtitle,
    required this.modules,
    required this.onSelect,
    required this.onRefresh,
  });

  IconData _moduleIcon(String key) {
    switch (key) {
      case 'delivery':
        return Icons.local_shipping_rounded;
      case 'market':
        return Icons.storefront_rounded;
      default:
        return Icons.local_taxi_rounded;
    }
  }

  Color _moduleTint(String key, bool dark) {
    if (dark) return const Color(0xFF202A3D);
    switch (key) {
      case 'delivery':
        return const Color(0xFFFFF0DD);
      case 'market':
        return const Color(0xFFEAF7EE);
      default:
        return const Color(0xFFEAF2FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = _experienceDark(context);
    final surface = _experienceSurface(context);
    final text = dark ? Colors.white : const Color(0xFF101828);
    final muted = _experienceMuted(context);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Row(
              children: [
                const ExpressOfficialLogo(size: 46, radius: 15),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EXPRESS',
                        style: TextStyle(
                          color: text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.7,
                        ),
                      ),
                      Text(
                        zoneName,
                        style: TextStyle(
                          color: muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar servicios',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(
              title,
              style: TextStyle(
                color: text,
                fontSize: 30,
                height: 1.02,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: muted,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720 ? 3 : 2;
                final gap = 12.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: modules.map((module) {
                    final key = module['module_key']?.toString() ?? 'ride';
                    final moduleTitle =
                        module['title']?.toString() ?? 'Servicio';
                    final moduleSubtitle =
                        module['subtitle']?.toString() ?? '';
                    return SizedBox(
                      width: width,
                      height: 190,
                      child: Material(
                        color: surface,
                        borderRadius: BorderRadius.circular(22),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onSelect(key),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 178),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _experienceBorder(context),
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: _moduleTint(key, dark),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Icon(
                                    _moduleIcon(key),
                                    color: _blue,
                                    size: 31,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  moduleTitle,
                                  style: TextStyle(
                                    color: text,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (moduleSubtitle.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    moduleSubtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                      height: 1.25,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF172033)
                    : const Color(0xFFF1F5FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, color: _blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Los servicios de esta pantalla dependen de la zona y de lo que administración tenga habilitado.',
                      style: TextStyle(
                        color: text,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerHome extends StatelessWidget {
  final ExpressService service;
  final VoidCallback onChanged;
  const _CustomerHome({required this.service, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => onChanged(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: [
            const _TopBrand(role: 'Cliente'),
            const SizedBox(height: 22),
            const Text('¿Qué necesitas hoy?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Viajes y envíos conectados a tu cuenta real.', style: TextStyle(color: _muted)),
            const SizedBox(height: 22),
            _ServiceCard(
              icon: Icons.local_taxi_rounded,
              title: 'Pedir un viaje',
              subtitle: 'Solicita un conductor y recibe ofertas.',
              button: 'Solicitar viaje',
              onTap: () async {
                final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _CreateRidePage(service: service)));
                if (changed == true) onChanged();
              },
            ),
            const SizedBox(height: 14),
            const SizedBox(height: 24),
            const _InfoCard(
              icon: Icons.verified_user_outlined,
              title: 'Datos reales',
              text: 'Las solicitudes creadas aquí se guardan en Supabase y pueden ser vistas por conductores aprobados.',
            ),
          ],
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>?> _chooseSavedAddress(
  BuildContext context,
  ExpressService service,
) async {
  final rows = await service.savedAddresses();
  if (!context.mounted) return null;

  if (rows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Todavía no tienes direcciones guardadas.'),
      ),
    );
    return null;
  }

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          const Text(
            'Direcciones guardadas',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.location_on_outlined),
              ),
              title: Text(row['label']?.toString() ?? 'Dirección'),
              subtitle: Text(row['address']?.toString() ?? ''),
              onTap: () => Navigator.pop(sheetContext, row),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CreateRidePage extends StatefulWidget {
  final ExpressService service;
  const _CreateRidePage({required this.service});

  @override
  State<_CreateRidePage> createState() => _CreateRidePageState();
}

class _CreateRidePageState extends State<_CreateRidePage> {
  final pickup = TextEditingController();
  final destination = TextEditingController();
  final fare = TextEditingController(text: '5');
  String category = 'motorcycle';
  String payment = 'cash';
  bool busy = false;
  bool checkingSpecialFare = false;
  Map<String, dynamic>? specialFare;
  double? pickupLatitude;
  double? pickupLongitude;
  double? destinationLatitude;
  double? destinationLongitude;

  Future<void> _refreshSpecialFare() async {
    if (pickupLatitude == null ||
        pickupLongitude == null ||
        destinationLatitude == null ||
        destinationLongitude == null) {
      if (mounted && specialFare != null) {
        setState(() => specialFare = null);
      }
      return;
    }

    setState(() => checkingSpecialFare = true);
    try {
      final result = await widget.service.specialFareForRoute(
        serviceKey: category,
        pickupLatitude: pickupLatitude!,
        pickupLongitude: pickupLongitude!,
        destinationLatitude: destinationLatitude!,
        destinationLongitude: destinationLongitude!,
      );
      if (!mounted) return;
      final matched = result['matched'] == true;
      if (matched) {
        final amount = _asDouble(result['amount']);
        if (amount != null && amount > 0) {
          final currency =
              result['currency']?.toString().toUpperCase() ?? 'BOB';
          fare.text = currency == 'CLP'
              ? amount.round().toString()
              : (amount == amount.roundToDouble()
                  ? amount.toStringAsFixed(0)
                  : amount.toStringAsFixed(2));
        }
      }
      setState(() {
        specialFare = matched ? result : null;
        checkingSpecialFare = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          specialFare = null;
          checkingSpecialFare = false;
        });
      }
    }
  }

  Future<void> _pickLocation({required bool pickupPoint}) async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: pickupPoint ? 'Seleccionar origen' : 'Seleccionar destino',
          initialLabel: pickupPoint ? pickup.text : destination.text,
          initialLatitude:
              pickupPoint ? pickupLatitude : destinationLatitude,
          initialLongitude:
              pickupPoint ? pickupLongitude : destinationLongitude,
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      if (pickupPoint) {
        pickup.text = result.label;
        pickupLatitude = result.latitude;
        pickupLongitude = result.longitude;
      } else {
        destination.text = result.label;
        destinationLatitude = result.latitude;
        destinationLongitude = result.longitude;
      }
    });
    await _refreshSpecialFare();
  }

  Future<void> _useSavedAddress({required bool pickupPoint}) async {
    final row = await _chooseSavedAddress(context, widget.service);
    if (row == null || !mounted) return;

    setState(() {
      final address = row['address']?.toString() ?? '';
      final latitude = _asDouble(row['latitude']);
      final longitude = _asDouble(row['longitude']);
      if (pickupPoint) {
        pickup.text = address;
        pickupLatitude = latitude;
        pickupLongitude = longitude;
      } else {
        destination.text = address;
        destinationLatitude = latitude;
        destinationLongitude = longitude;
      }
    });
    await _refreshSpecialFare();
  }

  @override
  void dispose() {
    pickup.dispose();
    destination.dispose();
    fare.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final amount = num.tryParse(fare.text.replaceAll(',', '.'));
    if (pickup.text.trim().isEmpty || destination.text.trim().isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa origen, destino y tarifa.')));
      return;
    }
    setState(() => busy = true);
    try {
      await widget.service.createRideRequest(
        category: category,
        pickupAddress: pickup.text.trim(),
        destinationAddress: destination.text.trim(),
        proposedFare: amount,
        paymentMethod: payment,
        pickupLatitude: pickupLatitude,
        pickupLongitude: pickupLongitude,
        destinationLatitude: destinationLatitude,
        destinationLongitude: destinationLongitude,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear el viaje: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar viaje')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: pickup,
            decoration: InputDecoration(
              labelText: 'Punto de partida',
              prefixIcon: const Icon(Icons.my_location_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Direcciones guardadas',
                    onPressed: () => _useSavedAddress(pickupPoint: true),
                    icon: const Icon(Icons.bookmark_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Elegir en mapa',
                    onPressed: () => _pickLocation(pickupPoint: true),
                    icon: Icon(
                      pickupLatitude == null
                          ? Icons.map_outlined
                          : Icons.check_circle_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: destination,
            decoration: InputDecoration(
              labelText: 'Destino',
              prefixIcon: const Icon(Icons.location_on_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Direcciones guardadas',
                    onPressed: () => _useSavedAddress(pickupPoint: false),
                    icon: const Icon(Icons.bookmark_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Elegir en mapa',
                    onPressed: () => _pickLocation(pickupPoint: false),
                    icon: Icon(
                      destinationLatitude == null
                          ? Icons.map_outlined
                          : Icons.check_circle_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Tipo de vehículo'),
            items: const [
              DropdownMenuItem(
                value: 'motorcycle',
                child: Text('Moto · Trinidad'),
              ),
            ],
            onChanged: (v) {
              setState(() => category = v ?? 'motorcycle');
              unawaited(_refreshSpecialFare());
            },
          ),
          const SizedBox(height: 12),
          if (checkingSpecialFare)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(),
            ),
          if (specialFare != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_rounded, color: _blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (Map<String, dynamic>.from(
                                specialFare!['special_zone'] as Map,
                              )['name']
                                  ?.toString() ??
                              'Zona especial') +
                          ' · tarifa fija ' +
                          _serviceMoney(
                            specialFare!['amount'],
                            specialFare!['currency'],
                          ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          TextField(
            controller: fare,
            readOnly: specialFare != null,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: specialFare != null
                  ? 'Tarifa fija de zona especial'
                  : 'Tarifa propuesta',
              prefixIcon: const Icon(Icons.payments_outlined),
              suffixIcon: specialFare != null
                  ? const Icon(Icons.lock_rounded)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: payment,
            decoration: const InputDecoration(labelText: 'Forma de pago'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
            ],
            onChanged: (v) => setState(() => payment = v ?? 'cash'),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: busy ? null : submit,
            icon: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.two_wheeler_rounded),
            label: const Text('Buscar conductor'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          ),
        ],
      ),
    );
  }
}

class _CreateDeliveryPage extends StatefulWidget {
  final ExpressService service;
  const _CreateDeliveryPage({required this.service});

  @override
  State<_CreateDeliveryPage> createState() => _CreateDeliveryPageState();
}

class _CreateDeliveryPageState extends State<_CreateDeliveryPage> {
  final pickup = TextEditingController();
  final dropoff = TextEditingController();
  final details = TextEditingController();
  final fare = TextEditingController(text: '8');
  String packageType = 'package';
  String payment = 'cash';
  bool busy = false;
  double? pickupLatitude;
  double? pickupLongitude;
  double? dropoffLatitude;
  double? dropoffLongitude;

  Future<void> _pickLocation({required bool pickupPoint}) async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: pickupPoint
              ? 'Seleccionar recogida'
              : 'Seleccionar entrega',
          initialLabel: pickupPoint ? pickup.text : dropoff.text,
          initialLatitude: pickupPoint ? pickupLatitude : dropoffLatitude,
          initialLongitude:
              pickupPoint ? pickupLongitude : dropoffLongitude,
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      if (pickupPoint) {
        pickup.text = result.label;
        pickupLatitude = result.latitude;
        pickupLongitude = result.longitude;
      } else {
        dropoff.text = result.label;
        dropoffLatitude = result.latitude;
        dropoffLongitude = result.longitude;
      }
    });
  }

  Future<void> _useSavedAddress({required bool pickupPoint}) async {
    final row = await _chooseSavedAddress(context, widget.service);
    if (row == null || !mounted) return;

    setState(() {
      final address = row['address']?.toString() ?? '';
      final latitude = _asDouble(row['latitude']);
      final longitude = _asDouble(row['longitude']);
      if (pickupPoint) {
        pickup.text = address;
        pickupLatitude = latitude;
        pickupLongitude = longitude;
      } else {
        dropoff.text = address;
        dropoffLatitude = latitude;
        dropoffLongitude = longitude;
      }
    });
  }

  @override
  void dispose() {
    pickup.dispose();
    dropoff.dispose();
    details.dispose();
    fare.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final amount = num.tryParse(fare.text.replaceAll(',', '.'));
    if (pickup.text.trim().isEmpty || dropoff.text.trim().isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa recogida, entrega y tarifa.')));
      return;
    }
    setState(() => busy = true);
    try {
      await widget.service.createDelivery(
        packageType: packageType,
        pickupAddress: pickup.text.trim(),
        dropoffAddress: dropoff.text.trim(),
        proposedFare: amount,
        paymentMethod: payment,
        details: details.text.trim().isEmpty ? null : details.text.trim(),
        pickupLatitude: pickupLatitude,
        pickupLongitude: pickupLongitude,
        dropoffLatitude: dropoffLatitude,
        dropoffLongitude: dropoffLongitude,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear el delivery: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo delivery')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: pickup,
            decoration: InputDecoration(
              labelText: 'Dirección de recogida',
              prefixIcon: const Icon(Icons.trip_origin_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Direcciones guardadas',
                    onPressed: () => _useSavedAddress(pickupPoint: true),
                    icon: const Icon(Icons.bookmark_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Elegir en mapa',
                    onPressed: () => _pickLocation(pickupPoint: true),
                    icon: Icon(
                      pickupLatitude == null
                          ? Icons.map_outlined
                          : Icons.check_circle_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: dropoff,
            decoration: InputDecoration(
              labelText: 'Dirección de entrega',
              prefixIcon: const Icon(Icons.location_on_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Direcciones guardadas',
                    onPressed: () => _useSavedAddress(pickupPoint: false),
                    icon: const Icon(Icons.bookmark_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Elegir en mapa',
                    onPressed: () => _pickLocation(pickupPoint: false),
                    icon: Icon(
                      dropoffLatitude == null
                          ? Icons.map_outlined
                          : Icons.check_circle_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: packageType,
            decoration: const InputDecoration(labelText: 'Tipo de envío'),
            items: const [
              DropdownMenuItem(value: 'document', child: Text('Documento')),
              DropdownMenuItem(value: 'package', child: Text('Paquete')),
              DropdownMenuItem(value: 'purchase', child: Text('Compra')),
              DropdownMenuItem(value: 'other', child: Text('Otro')),
            ],
            onChanged: (v) => setState(() => packageType = v ?? 'package'),
          ),
          const SizedBox(height: 12),
          TextField(controller: details, maxLines: 2, decoration: const InputDecoration(labelText: 'Detalles del envío')),
          const SizedBox(height: 12),
          TextField(controller: fare, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Tarifa propuesta', prefixIcon: Icon(Icons.payments_outlined))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: payment,
            decoration: const InputDecoration(labelText: 'Forma de pago'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
            ],
            onChanged: (v) => setState(() => payment = v ?? 'cash'),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: busy ? null : submit,
            icon: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.local_shipping_rounded),
            label: const Text('Buscar repartidor'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          ),
        ],
      ),
    );
  }
}

class _CustomerActivity extends StatefulWidget {
  final ExpressService service;
  final int revision;
  const _CustomerActivity({
    required this.service,
    required this.revision,
  });

  @override
  State<_CustomerActivity> createState() => _CustomerActivityState();
}

class _CustomerActivityState extends State<_CustomerActivity> {
  int refresh = 0;
  String filter = 'all';
  String period = 'today';
  late Future<_ActivityBundle> activityFuture;

  @override
  void initState() {
    super.initState();
    activityFuture = load();
  }

  @override
  void didUpdateWidget(covariant _CustomerActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      activityFuture = load();
    }
  }

  ({DateTime from, DateTime to}) _periodRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (period) {
      'week' => today.subtract(Duration(days: today.weekday - DateTime.monday)),
      'month' => DateTime(now.year, now.month),
      _ => today,
    };
    return (from: from, to: now.add(const Duration(seconds: 1)));
  }

  void _reload({String? nextPeriod}) {
    setState(() {
      if (nextPeriod != null) period = nextPeriod;
      refresh++;
      activityFuture = load();
    });
  }

  Future<_ActivityBundle> load() async {
    final range = _periodRange();
    final rides = await widget.service.myRideRequests(
      from: range.from,
      to: range.to,
      limit: 250,
    );
    final trips = await widget.service.myTrips(
      from: range.from,
      to: range.to,
      limit: 250,
    );
    final deliveries = await widget.service.myDeliveries(
      from: range.from,
      to: range.to,
      limit: 250,
    );

    final tripRequestIds = trips
        .map((trip) => trip['ride_request_id']?.toString())
        .whereType<String>()
        .toSet();

    final standaloneRides = rides
        .where(
          (ride) => !tripRequestIds.contains(ride['id']?.toString()),
        )
        .toList();

    return _ActivityBundle(
      standaloneRides,
      trips,
      deliveries,
    );
  }

  bool _scheduled(Map<String, dynamic> ride) {
    final raw = ride['scheduled_for']?.toString();
    if (raw == null || raw.isEmpty) return false;
    final date = DateTime.tryParse(raw)?.toLocal();
    return date != null && date.isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_ActivityBundle>(
        key: ValueKey('${widget.revision}-$refresh'),
        future: activityFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.all(18),
              children: const [
                _TopBrand(role: 'Historial'),
                SizedBox(height: 20),
                Text(
                  'Mis servicios',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 14),
                LinearProgressIndicator(),
                SizedBox(height: 14),
                _InfoCard(
                  icon: Icons.sync_rounded,
                  title: 'Actualizando servicios',
                  text: 'Estamos sincronizando tus viajes.',
                ),
              ],
            );
          }
          if (snapshot.hasError) {
            return _ErrorView(
              error: snapshot.error,
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;
          final scheduledRides =
              data.rides.where(_scheduled).toList();
          final regularRides =
              data.rides.where((ride) => !_scheduled(ride)).toList();

          final showRides = filter == 'all' || filter == 'rides';
          const showDelivery = false;
          final showScheduled = filter == 'scheduled';

          final visibleCount = showScheduled
              ? scheduledRides.length
              : (showRides ? regularRides.length + data.trips.length : 0);

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Historial'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mis servicios',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _experienceDark(context)
                            ? const Color(0xFF17315E)
                            : const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        visibleCount.toString(),
                        style: TextStyle(
                          color: _experienceDark(context)
                              ? const Color(0xFF9BC3FF)
                              : _blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActivityFilterChip(
                        label: 'Hoy',
                        icon: Icons.today_rounded,
                        selected: period == 'today',
                        onTap: () => _reload(nextPeriod: 'today'),
                      ),
                    ),
                    Expanded(
                      child: _ActivityFilterChip(
                        label: 'Semana',
                        icon: Icons.date_range_rounded,
                        selected: period == 'week',
                        onTap: () => _reload(nextPeriod: 'week'),
                      ),
                    ),
                    Expanded(
                      child: _ActivityFilterChip(
                        label: 'Mes',
                        icon: Icons.calendar_month_rounded,
                        selected: period == 'month',
                        onTap: () => _reload(nextPeriod: 'month'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ActivityFilterChip(
                        label: 'Todos',
                        icon: Icons.apps_rounded,
                        selected: filter == 'all',
                        onTap: () => setState(() => filter = 'all'),
                      ),
                      _ActivityFilterChip(
                        label: 'Viajes',
                        icon: Icons.local_taxi_rounded,
                        selected: filter == 'rides',
                        onTap: () => setState(() => filter = 'rides'),
                      ),

                      _ActivityFilterChip(
                        label: 'Programados',
                        icon: Icons.event_outlined,
                        selected: filter == 'scheduled',
                        onTap: () => setState(() => filter = 'scheduled'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (visibleCount == 0)
                  _InfoCard(
                    icon: showScheduled
                        ? Icons.event_busy_outlined
                        : Icons.inbox_outlined,
                    title: showScheduled
                        ? 'Sin viajes programados'
                        : 'Sin actividad',
                    text: showScheduled
                        ? 'Cuando programes un viaje futuro aparecerá aquí.'
                        : 'Tus viajes aparecerán aquí.',
                  )
                else if (showScheduled)
                  ...scheduledRides.map(
                    (ride) => _RideRequestCard(
                      service: widget.service,
                      ride: ride,
                      onChanged: _reload,
                    ),
                  )
                else ...[
                  if (showRides) ...[
                    ...regularRides.map(
                      (ride) => _RideRequestCard(
                        service: widget.service,
                        ride: ride,
                        onChanged: _reload,
                      ),
                    ),
                    ...data.trips.map(
                      (trip) => _TripCard(
                        service: widget.service,
                        trip: trip,
                        onChanged: _reload,
                      ),
                    ),
                  ],
                  if (showDelivery)
                    ...data.deliveries.map(
                      (delivery) => _DeliveryCard(
                        service: widget.service,
                        delivery: delivery,
                        onChanged: _reload,
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActivityFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ActivityFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: Icon(
          icon,
          size: 17,
          color: selected ? _blue : _muted,
        ),
        label: Text(label),
        selectedColor: _experienceDark(context)
            ? const Color(0xFF17315E)
            : const Color(0xFFEAF2FF),
        backgroundColor: _experienceSurface(context),
        side: BorderSide(
          color: selected ? _blue : _experienceBorder(context),
        ),
        labelStyle: TextStyle(
          color: selected ? (_experienceDark(context) ? const Color(0xFF9BC3FF) : _blue) : _experienceMuted(context),
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

Future<void> _showServiceDetails(
  BuildContext context,
  ExpressService service, {
  required String type,
  required Map<String, dynamic> data,
}) async {
  Map<String, dynamic> route = data;
  Map<String, dynamic>? counterpart;
  Map<String, dynamic>? driverProfile;

  if (type == 'trip') {
    final raw = data['ride_requests'];
    if (raw is Map) route = Map<String, dynamic>.from(raw);
    final driverId = data['driver_id']?.toString();
    if (driverId != null) {
      counterpart = await service.userById(driverId);
      driverProfile = await service.driverProfileById(driverId);
    }
  } else if (type == 'delivery') {
    final driverId = data['courier_id']?.toString();
    if (driverId != null) {
      counterpart = await service.userById(driverId);
      driverProfile = await service.driverProfileById(driverId);
    }
  }

  if (!context.mounted) return;

  String statusLabel(String? value) {
    switch (value) {
      case 'searching':
        return 'Buscando conductor';
      case 'offers_received':
        return 'Ofertas recibidas';
      case 'driver_assigned':
        return 'Conductor asignado';
      case 'driver_arriving':
        return 'Conductor en camino';
      case 'driver_waiting':
        return 'Conductor esperando';
      case 'in_progress':
        return 'En viaje';
      case 'completed':
        return 'Completado';
      case 'accepted':
        return 'Repartidor asignado';
      case 'picked_up':
        return 'Paquete recogido';
      case 'in_transit':
        return 'En camino';
      case 'delivered':
        return 'Entregado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return value ?? 'Sin estado';
    }
  }

  String paymentLabel(String? value) {
    switch (value) {
      case 'cash':
        return 'Efectivo';
      case 'wallet':
        return 'Billetera Express';
      case 'card':
        return 'Tarjeta';
      default:
        return value ?? 'No definido';
    }
  }

  String formatDate(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (parsed == null) return '—';
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return day +
        '/' +
        month +
        '/' +
        parsed.year.toString() +
        ' · ' +
        hour +
        ':' +
        minute;
  }

  final isDelivery = type == 'delivery';
  final isTrip = type == 'trip';
  final origin =
      isDelivery ? data['pickup_address'] : route['pickup_address'];
  final destination =
      isDelivery ? data['dropoff_address'] : route['destination_address'];
  final deliveryForCustomer = isDelivery &&
      data['marketplace_order_id'] != null &&
      data['customer_id']?.toString() == service.userId;
  final fare = isTrip
      ? data['final_fare'] ?? route['proposed_fare']
      : deliveryForCustomer
          ? data['customer_charge_amount'] ?? data['proposed_fare']
          : data['proposed_fare'];
  final currency = isTrip
      ? route['currency'] ?? data['currency']
      : data['currency'];
  final payment =
      isTrip ? route['payment_method'] : data['payment_method'];
  final scheduled =
      isTrip ? route['scheduled_for'] : data['scheduled_for'];

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _experienceDark(context)
                      ? const Color(0xFF17315E)
                      : const Color(0xFFEAF2FF),
                  child: Icon(
                    isDelivery
                        ? Icons.local_shipping_rounded
                        : Icons.local_taxi_rounded,
                    color: _blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDelivery
                            ? 'Detalle del delivery'
                            : isTrip
                                ? 'Detalle del viaje'
                                : 'Detalle de la solicitud',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        statusLabel(data['status']?.toString()),
                        style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _ServiceDetailRow(
              icon: Icons.trip_origin_rounded,
              label: 'Origen',
              value: origin?.toString() ?? '—',
            ),
            _ServiceDetailRow(
              icon: Icons.location_on_rounded,
              label: 'Destino',
              value: destination?.toString() ?? '—',
            ),
            _ServiceDetailRow(
              icon: Icons.payments_outlined,
              label: 'Tarifa',
              value: fare == null
                  ? '—'
                  : _serviceMoney(fare, currency),
            ),
            _ServiceDetailRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Pago',
              value: paymentLabel(payment?.toString()),
            ),
            if (!isDelivery)
              _ServiceDetailRow(
                icon: Icons.directions_car_outlined,
                label: 'Servicio',
                value: route['category']?.toString() ?? 'Express',
              ),
            if (scheduled != null)
              _ServiceDetailRow(
                icon: Icons.event_outlined,
                label: 'Programado',
                value: formatDate(scheduled),
              ),
            _ServiceDetailRow(
              icon: Icons.schedule_rounded,
              label: 'Creado',
              value: formatDate(data['created_at']),
            ),
            if (counterpart != null) ...[
              const Divider(height: 30),
              const Text(
                'Persona asignada',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              _ServiceDetailRow(
                icon: Icons.person_outline_rounded,
                label: isDelivery ? 'Repartidor' : 'Conductor',
                value:
                    counterpart['full_name']?.toString().trim().isNotEmpty ==
                            true
                        ? counterpart['full_name'].toString()
                        : 'Usuario Express',
              ),
              if (driverProfile?['vehicle_summary'] != null)
                _ServiceDetailRow(
                  icon: Icons.directions_car_filled_outlined,
                  label: 'Vehículo',
                  value: driverProfile!['vehicle_summary'].toString(),
                ),
              if (driverProfile?['rating'] != null)
                _ServiceDetailRow(
                  icon: Icons.star_outline_rounded,
                  label: 'Calificación',
                  value: driverProfile!['rating'].toString(),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ServiceDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ServiceDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _blue, size: 21),
          const SizedBox(width: 11),
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askCancellationReason(
  BuildContext context,
  String serviceName,
) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Cancelar $serviceName'),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Motivo (opcional)',
          hintText: 'Ej. Cambié de planes',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Confirmar cancelación'),
        ),
      ],
    ),
  );
  final reason = confirmed == true ? controller.text.trim() : null;
  controller.dispose();
  return reason;
}

class _RideRequestCard extends StatelessWidget {
  final ExpressService service;
  final Map<String, dynamic> ride;
  final VoidCallback onChanged;
  const _RideRequestCard({required this.service, required this.ride, required this.onChanged});

  Future<void> offers(BuildContext context) async {
    try {
      final list = await service.offersForRide(ride['id'].toString());
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ofertas de conductores', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Todavía no hay ofertas.'))
                else
                  ...list.map((offer) {
                    final driver = offer['driver_profiles'];
                    final info = driver is Map ? Map<String, dynamic>.from(driver) : <String, dynamic>{};
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                        title: Text(_serviceMoney(offer['proposed_fare'], ride['currency']) + ' · ${offer['eta_minutes'] ?? '?'} min'),
                        subtitle: Text('★ ${info['rating'] ?? '5'} · ${info['vehicle_summary'] ?? 'Vehículo por confirmar'}'),
                        trailing: offer['status'] == 'pending'
                            ? FilledButton(
                                onPressed: () async {
                                  try {
                                    await service.selectRideOffer(offer['id'].toString());
                                    if (!sheetContext.mounted) return;
                                    Navigator.pop(sheetContext);
                                    onChanged();
                                  } catch (e) {
                                    if (!sheetContext.mounted) return;
                                    ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text('No se pudo seleccionar: $e')));
                                  }
                                },
                                child: const Text('Elegir'),
                              )
                            : Text(offer['status'].toString()),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudieron cargar las ofertas: $e')));
    }
  }

  Future<void> cancel(BuildContext context) async {
    final reason = await _askCancellationReason(context, 'solicitud');
    if (reason == null || !context.mounted) return;
    try {
      await service.cancelRideRequest(
        ride['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud cancelada.')),
      );
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cancellable = ['searching', 'offers_received'].contains(ride['status']);
    return _RecordCard(
      icon: Icons.local_taxi_rounded,
      title: '${ride['pickup_address']} → ${ride['destination_address']}',
      subtitle: 'Viaje · ${ride['status']} · ' + _serviceMoney(ride['proposed_fare'], ride['currency']),
      onTap: () => _showServiceDetails(
        context,
        service,
        type: 'ride_request',
        data: ride,
      ),
      action: cancellable
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => offers(context),
                  child: const Text('Ofertas'),
                ),
                IconButton(
                  tooltip: 'Cancelar solicitud',
                  onPressed: () => cancel(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            )
          : null,
    );
  }
}

class _TripCard extends StatelessWidget {
  final ExpressService service;
  final Map<String, dynamic> trip;
  final VoidCallback onChanged;
  const _TripCard({
    required this.service,
    required this.trip,
    required this.onChanged,
  });

  Future<void> cancel(BuildContext context) async {
    final reason = await _askCancellationReason(context, 'viaje');
    if (reason == null || !context.mounted) return;
    try {
      await service.cancelTrip(
        trip['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viaje cancelado.')),
      );
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = trip['ride_requests'];
    final rideMap = ride is Map
        ? Map<String, dynamic>.from(ride)
        : <String, dynamic>{};
    final route = ride is Map
        ? '${ride['pickup_address'] ?? 'Origen'} → ${ride['destination_address'] ?? 'Destino'}'
        : 'Viaje';
    final status = trip['status']?.toString();
    final cancellable = trip['passenger_id'] == service.userId &&
        ['driver_assigned', 'driver_arriving', 'driver_waiting'].contains(status);
    final driverId = trip['driver_id']?.toString();
    return _RecordCard(
      icon: Icons.route_rounded,
      title: route,
      subtitle: 'Estado: ${trip['status']} · ' + _serviceMoney(trip['final_fare'], rideMap['currency']),
      onTap: () => _showServiceDetails(
        context,
        service,
        type: 'trip',
        data: trip,
      ),
      action: driverId == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Ver mapa',
                  onPressed: () {
                    final rideMap = ride is Map
                        ? Map<String, dynamic>.from(ride)
                        : <String, dynamic>{};
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceTrackingPage(
                          title: 'Seguimiento del viaje',
                          status: status ?? '',
                          driverId: driverId,
                          pickupLatitude:
                              _asDouble(rideMap['pickup_latitude']),
                          pickupLongitude:
                              _asDouble(rideMap['pickup_longitude']),
                          destinationLatitude:
                              _asDouble(rideMap['destination_latitude']),
                          destinationLongitude:
                              _asDouble(rideMap['destination_longitude']),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_outlined),
                ),
                if (cancellable)
                  IconButton(
                    tooltip: 'Cancelar viaje',
                    onPressed: () => cancel(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final ExpressService service;
  final Map<String, dynamic> delivery;
  final VoidCallback onChanged;
  const _DeliveryCard({
    required this.service,
    required this.delivery,
    required this.onChanged,
  });

  Future<void> cancel(BuildContext context) async {
    final reason = await _askCancellationReason(context, 'delivery');
    if (reason == null || !context.mounted) return;
    try {
      await service.cancelDelivery(
        delivery['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery cancelado.')),
      );
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = delivery['status']?.toString();
    final cancellable = delivery['customer_id'] == service.userId &&
        ['searching', 'accepted'].contains(status);
    final courierId = delivery['courier_id']?.toString();
    return _RecordCard(
      icon: Icons.local_shipping_rounded,
      title: '${delivery['pickup_address']} → ${delivery['dropoff_address']}',
      subtitle: 'Delivery · ' +
          (delivery['status']?.toString() ?? '') +
          ' · ' +
          _serviceMoney(
            delivery['marketplace_order_id'] != null
                ? delivery['customer_charge_amount'] ??
                    delivery['proposed_fare']
                : delivery['proposed_fare'],
            delivery['currency'],
          ),
      onTap: () => _showServiceDetails(
        context,
        service,
        type: 'delivery',
        data: delivery,
      ),
      action: courierId == null && !cancellable
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (courierId != null)
                  IconButton(
                    tooltip: 'Ver mapa',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceTrackingPage(
                          title: 'Seguimiento del delivery',
                          status: status ?? '',
                          driverId: courierId,
                          pickupLatitude:
                              _asDouble(delivery['pickup_latitude']),
                          pickupLongitude:
                              _asDouble(delivery['pickup_longitude']),
                          destinationLatitude:
                              _asDouble(delivery['dropoff_latitude']),
                          destinationLongitude:
                              _asDouble(delivery['dropoff_longitude']),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.map_outlined),
                  ),
                if (cancellable)
                  IconButton(
                    tooltip: 'Cancelar delivery',
                    onPressed: () => cancel(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
    );
  }
}

class _PaymentsPage extends StatefulWidget {
  final ExpressService service;
  final int revision;
  const _PaymentsPage({required this.service, required this.revision});

  @override
  State<_PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<_PaymentsPage> {
  int refresh = 0;

  Future<_PaymentsBundle> _load() async {
    final wallet = await widget.service.myWallet();
    final walletMovements = await widget.service.walletTransactions();
    final payments = await widget.service.myPayments();
    return _PaymentsBundle(
      wallet: wallet,
      walletMovements: walletMovements,
      payments: payments,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_PaymentsBundle>(
        key: ValueKey('${widget.revision}-$refresh'),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.all(18),
              children: const [
                _TopBrand(role: 'Pagos'),
                SizedBox(height: 20),
                Text(
                  'Billetera Express',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 14),
                LinearProgressIndicator(),
                SizedBox(height: 14),
                _InfoCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Actualizando billetera',
                  text: 'Estamos sincronizando tu saldo y movimientos.',
                ),
              ],
            );
          }

          if (snapshot.hasError) {
            return _ErrorView(
              error: snapshot.error,
              onRetry: () => setState(() => refresh++),
            );
          }

          final data = snapshot.data ??
              const _PaymentsBundle(
                wallet: <String, dynamic>{},
                walletMovements: <Map<String, dynamic>>[],
                payments: <Map<String, dynamic>>[],
              );
          final balance = data.wallet['balance'] ?? 0;
          final currency = data.wallet['currency'] ?? 'BOB';

          return RefreshIndicator(
            onRefresh: () async => setState(() => refresh++),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Pagos'),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B1739), _blue],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Billetera Express',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '$currency $balance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Saldo disponible',
                        style: TextStyle(color: Color(0xFFDCEAFF)),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Los pagos hechos con Billetera Express se procesan automáticamente al completar el servicio.',
                        style: TextStyle(
                          color: Color(0xFFBFD8FF),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Movimientos de billetera',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                if (data.walletMovements.isEmpty)
                  const _InfoCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'Sin movimientos todavía',
                    text:
                        'Aquí aparecerán pagos, devoluciones y ganancias de la billetera.',
                  )
                else
                  ...data.walletMovements.map((row) {
                    final amount = row['amount'];
                    final positive = amount is num
                        ? amount >= 0
                        : !amount.toString().startsWith('-');
                    return _RecordCard(
                      icon: positive
                          ? Icons.add_circle_outline_rounded
                          : Icons.remove_circle_outline_rounded,
                      title:
                          '${positive ? '+' : ''}${row['amount']} ${data.wallet['currency'] ?? 'BOB'}',
                      subtitle:
                          '${_walletMovementLabel(row['type']?.toString())} · ${row['status'] ?? ''}',
                    );
                  }),
                const SizedBox(height: 22),
                const Text(
                  'Pagos de servicios',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                if (data.payments.isEmpty)
                  const _InfoCard(
                    icon: Icons.payments_outlined,
                    title: 'Sin pagos registrados',
                    text: 'Los pagos de tus viajes aparecerán aquí.',
                  )
                else
                  ...data.payments.map(
                    (row) => _RecordCard(
                      icon: row['method'] == 'cash'
                          ? Icons.payments_outlined
                          : row['method'] == 'wallet'
                              ? Icons.account_balance_wallet_outlined
                              : Icons.credit_card_rounded,
                      title:
                          '${row['currency'] ?? 'BOB'} ${row['amount']}',
                      subtitle:
                          '${_paymentMethodLabel(row['method']?.toString())} · ${row['status']}',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _walletMovementLabel(String? type) {
    switch (type) {
      case 'topup':
        return 'Recarga';
      case 'payment':
        return 'Pago';
      case 'refund':
        return 'Devolución';
      case 'earning':
        return 'Ganancia';
      case 'adjustment':
        return 'Ajuste';
      default:
        return type ?? 'Movimiento';
    }
  }

  String _paymentMethodLabel(String? method) {
    switch (method) {
      case 'cash':
        return 'Efectivo';
      case 'wallet':
        return 'Billetera';
      case 'card':
        return 'Tarjeta';
      default:
        return method ?? 'Pago';
    }
  }
}

class _PaymentsBundle {
  final Map<String, dynamic> wallet;
  final List<Map<String, dynamic>> walletMovements;
  final List<Map<String, dynamic>> payments;

  const _PaymentsBundle({
    required this.wallet,
    required this.walletMovements,
    required this.payments,
  });
}

class _ProfilePage extends StatefulWidget {
  final ExpressService service;
  final bool driver;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;
  const _ProfilePage({required this.service, required this.driver, required this.onSwitchMode, required this.onExit});

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  int refresh = 0;

  Future<void> _editProfile(Map<String, dynamic>? user) async {
    final nameController = TextEditingController(
      text: user?['full_name']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: user?['phone']?.toString() ?? '',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (save != true || !mounted) {
      nameController.dispose();
      phoneController.dispose();
      return;
    }

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    nameController.dispose();
    phoneController.dispose();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede quedar vacío.')),
      );
      return;
    }

    try {
      await widget.service.updateProfile(
        fullName: name,
        phone: phone.isEmpty ? null : phone,
      );
      if (!mounted) return;
      setState(() => refresh++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>?>(
        key: ValueKey(refresh),
        future: widget.service.myUser(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          final email = supabase.auth.currentUser?.email ?? '';
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const _TopBrand(role: 'Perfil'),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: _cardDecoration(context),
                child: Row(children: [
                  const CircleAvatar(radius: 28, backgroundColor: _blue, child: Icon(Icons.person_rounded, color: Colors.white)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user?['full_name']?.toString().trim().isNotEmpty == true ? user!['full_name'].toString() : 'Usuario Express', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(email, style: const TextStyle(color: _muted)),
                    if (user?['phone'] != null) Text(user!['phone'].toString(), style: const TextStyle(color: _muted)),
                  ])),
                  IconButton(
                    tooltip: 'Editar perfil',
                    onPressed: () => _editProfile(user),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: Text(widget.driver ? 'Cambiar a modo Cliente' : 'Cambiar a modo Conductor'),
                subtitle: Text(widget.driver ? 'Volver a solicitar servicios' : 'Crear o abrir tu perfil de conductor'),
                onTap: widget.onSwitchMode,
              ),
              if (widget.driver)
                ListTile(
                  leading: const Icon(Icons.directions_car_filled_outlined),
                  title: const Text('Vehículo y documentos'),
                  subtitle: const Text('Configura el vehículo activo que usa el mapa y el despacho'),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DriverSetupPage(service: widget.service),
                      ),
                    );
                    if (mounted) setState(() => refresh++);
                  },
                ),
              if (widget.driver)
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Suscripción'),
                  subtitle: const Text(
                    'Plan, tiempo restante, beneficios y pago según tu zona',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverSubscriptionPage(),
                    ),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Mis direcciones'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _SavedAddressesPage(service: widget.service))),
              ),
              ListTile(
                leading: const Icon(Icons.security_outlined),
                title: const Text('Seguridad y contactos'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _SafetyPage(service: widget.service))),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Cerrar sesión'),
                onTap: widget.onExit,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DriverShell extends StatefulWidget {
  final ExpressService service;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;
  const _DriverShell({
    super.key,
    required this.service,
    required this.onSwitchMode,
    required this.onExit,
  });

  @override
  State<_DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<_DriverShell> {
  int index = 0;
  int revision = 0;
  bool driverInteractionLocked = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final navActive =
        dark ? const Color(0xFF9CC2FF) : const Color(0xFF0B57D0);
    final navInactive =
        dark ? const Color(0xFFB7BDC8) : const Color(0xFF667085);
    final navBackground =
        dark ? const Color(0xFF121212) : Colors.white;
    final navIndicator =
        dark ? const Color(0xFF17315E) : const Color(0xFFDDE8FF);

    final pages = [
      DriverMapHome(
        service: widget.service,
        revision: revision,
        onChanged: () => setState(() => revision++),
        onSwitchMode: widget.onSwitchMode,
        onHistory: () => setState(() => index = 1),
        onEarnings: () => setState(() => index = 2),
        onProfile: () => setState(() => index = 3),
        onSafety: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SafetyPage(service: widget.service),
          ),
        ),
        onRequestCountChanged: (_) {},
        onOfferPendingChanged: (locked) {
          if (!mounted || driverInteractionLocked == locked) return;
          setState(() {
            driverInteractionLocked = locked;
            if (locked) index = 0;
          });
        },
      ),
      ExpressHistoryPage(
        service: widget.service,
        driver: true,
      ),
      _DriverEarnings(
        service: widget.service,
        revision: revision,
      ),
      ExpressWalletPage(
        service: widget.service,
        driver: true,
      ),
      ExpressProfileHubPage(
        service: widget.service,
        driver: true,
        onSwitchMode: widget.onSwitchMode,
        onExit: widget.onExit,
        onSavedAddresses: () {},
        onSafety: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SafetyPage(service: widget.service),
          ),
        ),
      ),
    ];


    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: driverInteractionLocked ? .48 : 1,
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: navBackground,
            indicatorColor: navIndicator,
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
              (states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? navActive
                    : navInactive,
              ),
            ),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
              (states) => TextStyle(
                color: states.contains(WidgetState.selected)
                    ? navActive
                    : navInactive,
                fontSize: 12,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
          ),
          child: NavigationBar(
            height: 72,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: index,
            onDestinationSelected: driverInteractionLocked
                ? null
                : (value) => setState(() => index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history_rounded),
                label: 'Historial',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart_rounded),
                label: 'Ganancias',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Billetera',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverRequestsInbox extends StatefulWidget {
  final ExpressService service;
  final int revision;
  final VoidCallback onChanged;
  final ValueChanged<int> onCountChanged;

  const _DriverRequestsInbox({
    required this.service,
    required this.revision,
    required this.onChanged,
    required this.onCountChanged,
  });

  @override
  State<_DriverRequestsInbox> createState() => _DriverRequestsInboxState();
}

class _DriverRequestsInboxState extends State<_DriverRequestsInbox>
    with WidgetsBindingObserver {
  Timer? countdownTimer;
  Timer? safetySyncTimer;
  Timer? realtimeDebounce;
  RealtimeChannel? requestsChannel;
  bool sending = false;
  late Future<List<Map<String, dynamic>>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestsFuture = _load();

    // El contador visual necesita refrescarse cada segundo, pero eso NO debe
    // disparar una consulta nueva al backend.
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Realtime es la vía principal: cualquier INSERT/UPDATE/DELETE en
    // ride_requests provoca una revalidación inmediata contra el RPC
    // autoritativo available_ride_requests_for_driver.
    requestsChannel = supabase
        .channel('driver-requests-inbox-${widget.service.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_requests',
          callback: (_) {
            realtimeDebounce?.cancel();
            realtimeDebounce = Timer(
              const Duration(milliseconds: 250),
              _reloadRequests,
            );
          },
        )
        .subscribe();

    // Respaldo por si Android perdió temporalmente un evento Realtime.
    // No reemplaza Realtime y nunca usa datos cacheados para solicitudes.
    safetySyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _reloadRequests();
    });
  }

  @override
  void didUpdateWidget(covariant _DriverRequestsInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _reloadRequests();
    }
  }

  void _reloadRequests() {
    if (!mounted) return;
    setState(() {
      _requestsFuture = _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Al volver del segundo plano se consulta inmediatamente al backend.
      // Esto evita mostrar solicitudes o contadores congelados.
      _reloadRequests();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    countdownTimer?.cancel();
    safetySyncTimer?.cancel();
    realtimeDebounce?.cancel();
    final channel = requestsChannel;
    if (channel != null) {
      unawaited(supabase.removeChannel(channel));
    }
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final profile = await widget.service.myDriverProfile();
    if (profile == null ||
        profile['approval_status'] != 'approved' ||
        profile['online_status'] != 'online') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCountChanged(0);
      });
      return const [];
    }

    final rows = await widget.service.availableRideRequests();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCountChanged(rows.length);
    });
    return rows;
  }

  String _remaining(Map<String, dynamic> ride) {
    final expires =
        DateTime.tryParse(ride['expires_at']?.toString() ?? '')?.toUtc();
    if (expires == null) return '--:--';
    final seconds =
        expires.difference(DateTime.now().toUtc()).inSeconds.clamp(0, 5999);
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return minutes.toString().padLeft(2, '0') +
        ':' +
        rest.toString().padLeft(2, '0');
  }

  Future<void> _accept(Map<String, dynamic> ride) async {
    final fare = _asDouble(ride['proposed_fare']);
    if (fare == null || fare <= 0 || sending) return;
    setState(() => sending = true);
    try {
      await widget.service.createRideOffer(
        rideRequestId: ride['id'].toString(),
        fare: fare,
        etaMinutes: 5,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tarifa aceptada. Esperando confirmación del pasajero.',
          ),
        ),
      );
      widget.onChanged();
      _reloadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aceptar: ' + e.toString())),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _offer(Map<String, dynamic> ride) async {
    final controller = TextEditingController(
      text: ride['proposed_fare']?.toString() ?? '',
    );
    final amount = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ofertar otro monto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Tu tarifa',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = num.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              if (value != null && value > 0) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Enviar oferta'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted || sending) return;

    setState(() => sending = true);
    try {
      await widget.service.createRideOffer(
        rideRequestId: ride['id'].toString(),
        fare: amount,
        etaMinutes: 5,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Oferta de ' +
                _serviceMoney(amount, ride['currency']) +
                ' enviada al pasajero.',
          ),
        ),
      );
      widget.onChanged();
      _reloadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo ofertar: ' + e.toString())),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _requestsFuture,
        builder: (context, snapshot) {
          final rides = snapshot.data ?? const <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: () async => _reloadRequests(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Solicitudes',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 38),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: rides.isEmpty
                            ? const Color(0xFFF2F4F7)
                            : _blue,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        rides.length.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: rides.isEmpty ? _muted : Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Aquí quedan las solicitudes activas aunque ya haya terminado su aviso emergente de 45 segundos.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    snapshot.data == null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (snapshot.hasError)
                  _ErrorView(
                    error: snapshot.error,
                    onRetry: _reloadRequests,
                  )
                else if (rides.isEmpty)
                  const _InfoCard(
                    icon: Icons.radar_rounded,
                    title: 'No hay solicitudes activas',
                    text:
                        'Cuando un pasajero solicite un viaje, aparecerá aquí y también se mostrará el aviso automático en Inicio.',
                  )
                else
                  ...rides.map((ride) {
                    final pickup =
                        ride['pickup_address']?.toString() ?? 'Origen';
                    final destination =
                        ride['destination_address']?.toString() ?? 'Destino';
                    final fare = _asDouble(ride['proposed_fare']) ?? 0;
                    final category =
                        ride['category']?.toString() ?? 'Viaje';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _experienceSurface(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _experienceBorder(context),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _experienceDark(context)
                                ? const Color(0x66000000)
                                : const Color(0x10000000),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFFEAF2FF),
                                child: Icon(
                                  Icons.local_taxi_rounded,
                                  color: _blue,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _serviceMoney(fare, ride['currency']),
                                    style: const TextStyle(
                                      color: _blue,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    _remaining(ride),
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            pickup + ' → ' + destination,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: sending
                                      ? null
                                      : () => _offer(ride),
                                  child: const Text('Ofertar'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  onPressed: sending
                                      ? null
                                      : () => _accept(ride),
                                  child: const Text('Aceptar tarifa'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DriverHome extends StatefulWidget {
  final ExpressService service;
  final int revision;
  final VoidCallback onChanged;
  const _DriverHome({required this.service, required this.revision, required this.onChanged});

  @override
  State<_DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<_DriverHome> {
  int refresh = 0;
  bool busy = false;
  StreamSubscription? _positionSubscription;
  final locationService = const ExpressLocationService();

  void _startLocationTracking() {
    if (_positionSubscription != null) return;
    _positionSubscription = locationService.positionStream().listen(
      (position) async {
        try {
          await widget.service.updateDriverDetails(
            latitude: position.latitude,
            longitude: position.longitude,
          );
        } catch (_) {
          // El siguiente evento volverá a intentar sincronizar la ubicación.
        }
      },
      onError: (_) {},
    );
  }

  Future<void> _stopLocationTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<_DriverBundle> load() async {
    final profile = await widget.service.myDriverProfile() ??
        await widget.service.ensureDriverProfile();
    List<Map<String, dynamic>> rides = [];
    List<Map<String, dynamic>> deliveries = [];

    if (profile['approval_status'] == 'approved' &&
        ['online', 'busy'].contains(profile['online_status'])) {
      _startLocationTracking();

      final vehicles = await widget.service.myVehicles();
      final vehicleTypes = vehicles
          .where((vehicle) => vehicle['is_active'] == true)
          .map((vehicle) => vehicle['vehicle_type']?.toString())
          .whereType<String>()
          .toSet();

      rides = (await widget.service.availableRideRequests())
          .where((ride) => _rideMatchesVehicle(
                ride['category']?.toString() ?? 'economy',
                vehicleTypes,
              ))
          .toList();
      deliveries = const [];

      final latitude = _asDouble(profile['latitude']);
      final longitude = _asDouble(profile['longitude']);
      if (latitude != null && longitude != null) {
        double distanceTo(Map<String, dynamic> row, String latKey, String lngKey) {
          final lat = _asDouble(row[latKey]);
          final lng = _asDouble(row[lngKey]);
          if (lat == null || lng == null) return double.infinity;
          return locationService.distanceMeters(
            fromLatitude: latitude,
            fromLongitude: longitude,
            toLatitude: lat,
            toLongitude: lng,
          );
        }

        rides.sort(
          (a, b) => distanceTo(a, 'pickup_latitude', 'pickup_longitude')
              .compareTo(
            distanceTo(b, 'pickup_latitude', 'pickup_longitude'),
          ),
        );
        deliveries.sort(
          (a, b) => distanceTo(a, 'pickup_latitude', 'pickup_longitude')
              .compareTo(
            distanceTo(b, 'pickup_latitude', 'pickup_longitude'),
          ),
        );
      }
    }

    return _DriverBundle(profile, rides, deliveries);
  }

  bool _rideMatchesVehicle(String category, Set<String> vehicleTypes) {
    if (vehicleTypes.isEmpty) return true;

    switch (category) {
      case 'motorcycle':
        return vehicleTypes.contains('motorcycle');
      case 'xl':
        return vehicleTypes.contains('xl');
      case 'comfort':
      case 'economy':
        return vehicleTypes.contains('car') || vehicleTypes.contains('xl');
      default:
        return true;
    }
  }

  String? _distanceLabel(
    Map<String, dynamic> profile,
    Map<String, dynamic> row,
  ) {
    final fromLat = _asDouble(profile['latitude']);
    final fromLng = _asDouble(profile['longitude']);
    final toLat = _asDouble(row['pickup_latitude']);
    final toLng = _asDouble(row['pickup_longitude']);
    if (fromLat == null || fromLng == null || toLat == null || toLng == null) {
      return null;
    }
    final meters = locationService.distanceMeters(
      fromLatitude: fromLat,
      fromLongitude: fromLng,
      toLatitude: toLat,
      toLongitude: toLng,
    );
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> toggleOnline(Map<String, dynamic> profile) async {
    setState(() => busy = true);
    try {
      final online = profile['online_status'] == 'online';
      if (online) {
        await widget.service.setDriverOnline(false);
        await _stopLocationTracking();
      } else {
        final accepted = await confirmExpressLocationUse(
          context,
          continuousDriverTracking: true,
        );
        if (!accepted || !mounted) return;

        final position = await locationService.currentPosition();
        await widget.service.updateDriverDetails(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        await widget.service.setDriverOnline(true);
        _startLocationTracking();
      }
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;

      final rawMessage = e is PostgrestException
          ? e.message.trim()
          : e.toString().replaceFirst('Exception: ', '').trim();

      final isSubscriptionError =
          rawMessage.toLowerCase().contains('suscripción') ||
          rawMessage.toLowerCase().contains('suscripcion');

      final title = isSubscriptionError
          ? 'Suscripción requerida'
          : 'No pudimos cambiar tu estado';

      final message = isSubscriptionError
          ? 'Tu suscripción no está activa. Activa o renueva tu plan para conectarte.'
          : rawMessage.isEmpty
              ? 'Inténtalo nuevamente en unos segundos.'
              : rawMessage;

      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            duration: const Duration(seconds: 5),
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isSubscriptionError
                      ? Icons.workspace_premium_rounded
                      : Icons.info_outline_rounded,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(message),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> offerRide(Map<String, dynamic> ride) async {
    final fareController = TextEditingController(
      text: ride['proposed_fare']?.toString() ?? '',
    );
    final etaController = TextEditingController(text: '5');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar oferta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${ride['pickup_address']} → ${ride['destination_address']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: fareController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tu tarifa',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: etaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Llegas en (minutos)',
                prefixIcon: Icon(Icons.schedule_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enviar oferta'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      fareController.dispose();
      etaController.dispose();
      return;
    }

    final fare = num.tryParse(
      fareController.text.trim().replaceAll(',', '.'),
    );
    final eta = int.tryParse(etaController.text.trim());
    fareController.dispose();
    etaController.dispose();

    if (fare == null || fare <= 0 || eta == null || eta <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa una tarifa y tiempo válidos.'),
        ),
      );
      return;
    }

    try {
      await widget.service.createRideOffer(
        rideRequestId: ride['id'].toString(),
        fare: fare,
        etaMinutes: eta,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oferta enviada al pasajero.')),
      );
      setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar la oferta: $e')),
      );
    }
  }

  Future<void> claimDelivery(Map<String, dynamic> delivery) async {
    try {
      await widget.service.claimDelivery(delivery['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery aceptado.')));
      widget.onChanged();
      setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo aceptar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_DriverBundle>(
        key: ValueKey('${widget.revision}-$refresh'),
        future: load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return _ErrorView(error: snapshot.error, onRetry: () => setState(() => refresh++));
          final data = snapshot.data!;
          final profile = data.profile;
          final approved = profile['approval_status'] == 'approved';
          final online = profile['online_status'] == 'online';
          return RefreshIndicator(
            onRefresh: () async => setState(() => refresh++),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Conductor'),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_blueDark, _blue]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Estado: ${profile['approval_status']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(profile['vehicle_summary']?.toString() ?? 'Completa tus datos de vehículo', style: const TextStyle(color: Color(0xFFDCEAFF))),
                    const SizedBox(height: 14),
                    if (approved)
                      FilledButton.icon(
                        onPressed: busy ? null : () => toggleOnline(profile),
                        icon: Icon(online ? Icons.toggle_on_rounded : Icons.toggle_off_rounded),
                        label: Text(online ? 'Quedar fuera de línea' : 'Ponerme en línea'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _blueDark),
                      )
                    else
                      const Text('Tu cuenta debe ser aprobada antes de recibir solicitudes.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 18),
                if (!approved)
                  const _InfoCard(icon: Icons.hourglass_top_rounded, title: 'Aprobación pendiente', text: 'Ya puedes completar tu perfil; las solicitudes se habilitan cuando el administrador aprueba al conductor.')
                else if (!online)
                  const _InfoCard(icon: Icons.visibility_off_outlined, title: 'Estás fuera de línea', text: 'Activa tu disponibilidad para recibir viajes.')
                else ...[
                  const Text('Viajes disponibles', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  if (data.rides.isEmpty) const Text('No hay viajes nuevos por ahora.', style: TextStyle(color: _muted)),
                  ...data.rides.map((ride) => _JobCard(
                        icon: Icons.local_taxi_rounded,
                        title: '${ride['pickup_address']} → ${ride['destination_address']}',
                        subtitle:
                            _serviceMoney(ride['proposed_fare'], ride['currency']) + ' · ${ride['category']}'
                            '${_distanceLabel(profile, ride) == null ? '' : ' · ${_distanceLabel(profile, ride)}'}',
                        button: 'Enviar oferta',
                        onTap: () => offerRide(ride),
                      )),

                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DriverServices extends StatefulWidget {
  final ExpressService service;
  final int revision;
  final VoidCallback onChanged;
  const _DriverServices({required this.service, required this.revision, required this.onChanged});

  @override
  State<_DriverServices> createState() => _DriverServicesState();
}

class _DriverServicesState extends State<_DriverServices> {
  int refresh = 0;
  late Future<_ActiveBundle> _servicesFuture;

  @override
  void initState() {
    super.initState();
    _servicesFuture = load();
  }

  @override
  void didUpdateWidget(covariant _DriverServices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _servicesFuture = load();
    }
  }

  void _reloadServices() {
    setState(() {
      refresh++;
      _servicesFuture = load();
    });
  }

  Future<_ActiveBundle> load() async {
    final trips = await widget.service.myTrips();
    final deliveries = await widget.service.myDeliveries();
    return _ActiveBundle(trips, deliveries);
  }

  String? nextTrip(String status) {
    switch (status) {
      case 'driver_assigned': return 'driver_waiting';
      case 'driver_arriving': return 'driver_waiting';
      case 'driver_waiting': return 'in_progress';
      case 'in_progress': return 'completed';
      default: return null;
    }
  }

  String? nextDelivery(String status) {
    switch (status) {
      case 'accepted': return 'picked_up';
      case 'picked_up': return 'in_transit';
      case 'in_transit': return 'delivered';
      default: return null;
    }
  }

  Future<void> advanceTrip(Map<String, dynamic> trip) async {
    final next = nextTrip(trip['status'].toString());
    if (next == null) return;
    try {
      if (next == 'in_progress') {
        final controller = TextEditingController();
        final pin = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('PIN de abordaje'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: '0000',
                helperText: 'Pide al pasajero su PIN de 4 dígitos.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.length == 4 && int.tryParse(value) != null) {
                    Navigator.pop(dialogContext, value);
                  }
                },
                child: const Text('Iniciar viaje'),
              ),
            ],
          ),
        );
        controller.dispose();
        if (pin == null || !mounted) return;
        await widget.service.startTripWithPin(
          tripId: trip['id'].toString(),
          pin: pin,
        );
      } else {
        await widget.service.advanceTrip(trip['id'].toString(), next);
      }
      if (mounted) _reloadServices();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo avanzar el viaje: $e')),
      );
    }
  }

  Future<void> advanceDelivery(Map<String, dynamic> delivery) async {
    final next = nextDelivery(delivery['status'].toString());
    if (next == null) return;
    try {
      await widget.service.advanceDelivery(delivery['id'].toString(), next);
      if (mounted) _reloadServices();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo avanzar el delivery: $e')));
    }
  }

  Future<void> cancelTrip(Map<String, dynamic> trip) async {
    final reason = await _askCancellationReason(context, 'viaje');
    if (reason == null || !mounted) return;
    try {
      await widget.service.cancelTrip(
        trip['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (mounted) _reloadServices();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar el viaje: $e')),
      );
    }
  }

  Future<void> cancelDelivery(Map<String, dynamic> delivery) async {
    final reason = await _askCancellationReason(context, 'delivery');
    if (reason == null || !mounted) return;
    try {
      await widget.service.cancelDelivery(
        delivery['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (mounted) _reloadServices();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar el delivery: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_ActiveBundle>(
        future: _servicesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error, onRetry: _reloadServices);
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reloadServices(),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Servicios'),
                const SizedBox(height: 20),
                const Text('Servicios asignados', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                ...data.trips.map((trip) {
                  final ride = trip['ride_requests'];
                  final rideMap = ride is Map
                      ? Map<String, dynamic>.from(ride)
                      : <String, dynamic>{};
                  final route = ride is Map ? '${ride['pickup_address']} → ${ride['destination_address']}' : 'Viaje';
                  final next = nextTrip(trip['status'].toString());
                  return _RecordCard(
                    icon: Icons.local_taxi_rounded,
                    title: route,
                    subtitle: 'Viaje · ${trip['status']} · ' + _serviceMoney(trip['final_fare'], rideMap['currency']),
                    action: next == null
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Ver mapa',
                                onPressed: () {
                                  final rideMap = ride is Map
                                      ? Map<String, dynamic>.from(ride)
                                      : <String, dynamic>{};
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ServiceTrackingPage(
                                        title: 'Ruta del viaje',
                                        status: trip['status']?.toString() ?? '',
                                        driverId: widget.service.userId,
                                        pickupLatitude:
                                            _asDouble(rideMap['pickup_latitude']),
                                        pickupLongitude:
                                            _asDouble(rideMap['pickup_longitude']),
                                        destinationLatitude:
                                            _asDouble(rideMap['destination_latitude']),
                                        destinationLongitude:
                                            _asDouble(rideMap['destination_longitude']),
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.map_outlined),
                              ),
                              FilledButton(
                                onPressed: () => advanceTrip(trip),
                                child: Text(_tripAction(next)),
                              ),
                              if (['driver_assigned', 'driver_arriving', 'driver_waiting']
                                  .contains(trip['status']))
                                IconButton(
                                  tooltip: 'Cancelar viaje',
                                  onPressed: () => cancelTrip(trip),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                  );
                }),
                ...data.deliveries.where((d) => d['courier_id'] == widget.service.userId).map((delivery) {
                  final next = nextDelivery(delivery['status'].toString());
                  return _RecordCard(
                    icon: Icons.local_shipping_rounded,
                    title: '${delivery['pickup_address']} → ${delivery['dropoff_address']}',
                    subtitle: 'Delivery · ' +
                        (delivery['status']?.toString() ?? '') +
                        ' · ' +
                        _serviceMoney(
                          delivery['proposed_fare'],
                          delivery['currency'],
                        ),
                    action: next == null
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Ver mapa',
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ServiceTrackingPage(
                                      title: 'Ruta del delivery',
                                      status: delivery['status']?.toString() ?? '',
                                      driverId: widget.service.userId,
                                      pickupLatitude:
                                          _asDouble(delivery['pickup_latitude']),
                                      pickupLongitude:
                                          _asDouble(delivery['pickup_longitude']),
                                      destinationLatitude:
                                          _asDouble(delivery['dropoff_latitude']),
                                      destinationLongitude:
                                          _asDouble(delivery['dropoff_longitude']),
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.map_outlined),
                              ),
                              FilledButton(
                                onPressed: () => advanceDelivery(delivery),
                                child: Text(_deliveryAction(next)),
                              ),
                              if (delivery['status'] == 'accepted')
                                IconButton(
                                  tooltip: 'Cancelar delivery',
                                  onPressed: () => cancelDelivery(delivery),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                  );
                }),
                if (data.trips.isEmpty && data.deliveries.where((d) => d['courier_id'] == widget.service.userId).isEmpty)
                  const _InfoCard(icon: Icons.route_outlined, title: 'Sin servicios asignados', text: 'Los viajes elegidos por pasajeros y los delivery aceptados aparecerán aquí.'),
              ],
            ),
          );
        },
      ),
    );
  }

  String _tripAction(String status) {
    switch (status) {
      case 'driver_arriving': return 'Llegué';
      case 'driver_waiting': return 'Llegué';
      case 'in_progress': return 'Iniciar viaje';
      case 'completed': return 'Completar';
      default: return status;
    }
  }

  String _deliveryAction(String status) {
    switch (status) {
      case 'picked_up': return 'Recogido';
      case 'in_transit': return 'En camino';
      case 'delivered': return 'Entregado';
      default: return status;
    }
  }
}

class _DriverEarnings extends StatefulWidget {
  final ExpressService service;
  final int revision;
  const _DriverEarnings({
    required this.service,
    required this.revision,
  });

  @override
  State<_DriverEarnings> createState() => _DriverEarningsState();
}

class _DriverEarningsState extends State<_DriverEarnings> {
  String period = 'today';
  int refresh = 0;
  late Future<_EarningsBundle> _earningsFuture;

  @override
  void initState() {
    super.initState();
    _earningsFuture = load();
  }

  @override
  void didUpdateWidget(covariant _DriverEarnings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _earningsFuture = load();
    }
  }

  void _reloadEarnings() {
    setState(() {
      refresh++;
      _earningsFuture = load();
    });
  }

  void _setPeriod(String value) {
    if (period == value) return;
    setState(() {
      period = value;
      _earningsFuture = load();
    });
  }

  DateTime? _fromDate() {
    final now = DateTime.now();
    switch (period) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'week':
        final today = DateTime(now.year, now.month, now.day);
        return today.subtract(Duration(days: today.weekday - 1));
      case 'month':
        return DateTime(now.year, now.month, 1);
      default:
        return null;
    }
  }

  bool _inPeriod(Map<String, dynamic> row) {
    final from = _fromDate();
    if (from == null) return true;
    final raw = row['completed_at'] ?? row['created_at'];
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return false;
    return !date.isBefore(from);
  }

  Future<_EarningsBundle> load() async {
    final trips = await widget.service.myTrips();
    final deliveries = await widget.service.myDeliveries();
    final wallet = await widget.service.myWallet();

    final completedTrips = trips
        .where(
          (t) =>
              t['driver_id'] == widget.service.userId &&
              t['status'] == 'completed' &&
              _inPeriod(t),
        )
        .toList();

    final completedDeliveries = deliveries
        .where(
          (d) =>
              d['courier_id'] == widget.service.userId &&
              d['status'] == 'delivered' &&
              _inPeriod(d),
        )
        .toList();

    final totals = <String, num>{};
    final counts = <String, int>{};

    void add(String currency, Object? value) {
      final code = expressCurrencyCode(currency);
      totals[code] = (totals[code] ?? 0) + (_asDouble(value) ?? 0);
      counts[code] = (counts[code] ?? 0) + 1;
    }

    for (final trip in completedTrips) {
      add(_tripCurrency(trip), trip['final_fare']);
    }
    for (final delivery in completedDeliveries) {
      add(
        expressCurrencyCode(delivery['currency']),
        delivery['proposed_fare'],
      );
    }

    return _EarningsBundle(
      totals: totals,
      currencyCounts: counts,
      count: completedTrips.length + completedDeliveries.length,
      trips: completedTrips,
      deliveries: completedDeliveries,
      defaultCurrency:
          expressCurrencyCode(wallet['currency'], fallback: 'BOB'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_EarningsBundle>(
        future: _earningsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              error: snapshot.error,
              onRetry: _reloadEarnings,
            );
          }

          final data = snapshot.data!;
          final tripTotals = _sumMoneyByCurrency(
            data.trips,
            (trip) => trip['final_fare'],
            _tripCurrency,
          );
          final deliveryTotals = _sumMoneyByCurrency(
            data.deliveries,
            (delivery) => delivery['proposed_fare'],
            (delivery) => expressCurrencyCode(delivery['currency']),
          );
          final totalEntries = data.totals.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));

          return RefreshIndicator(
            onRefresh: () async => _reloadEarnings(),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Ganancias'),
                const SizedBox(height: 20),
                const Text(
                  'Tus ganancias',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _EarningsPeriodChip(
                        label: 'Hoy',
                        selected: period == 'today',
                        onTap: () => _setPeriod('today'),
                      ),
                      _EarningsPeriodChip(
                        label: 'Esta semana',
                        selected: period == 'week',
                        onTap: () => _setPeriod('week'),
                      ),
                      _EarningsPeriodChip(
                        label: 'Este mes',
                        selected: period == 'month',
                        onTap: () => _setPeriod('month'),
                      ),
                      _EarningsPeriodChip(
                        label: 'Todo',
                        selected: period == 'all',
                        onTap: () => _setPeriod('all'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_blueDark, _blue],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ganancia registrada',
                        style: TextStyle(color: Color(0xFFDCEAFF)),
                      ),
                      const SizedBox(height: 4),
                      if (totalEntries.isEmpty) ...[
                        Text(
                          expressMoney(0, data.defaultCurrency),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '0 servicios',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else
                        ...totalEntries.map((entry) {
                          final count = data.currencyCounts[entry.key] ?? 0;
                          final average =
                              count == 0 ? 0 : entry.value / count;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  expressMoney(entry.value, entry.key),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  '$count servicios · promedio ' +
                                      expressMoney(average, entry.key),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _EarningMetric(
                        icon: Icons.local_taxi_rounded,
                        label: 'Viajes',
                        amounts: tripTotals,
                        count: data.trips.length,
                        defaultCurrency: data.defaultCurrency,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _EarningMetric(
                        icon: Icons.local_shipping_rounded,
                        label: 'Delivery',
                        amounts: deliveryTotals,
                        count: data.deliveries.length,
                        defaultCurrency: data.defaultCurrency,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (data.count == 0)
                  const _InfoCard(
                    icon: Icons.payments_outlined,
                    title: 'Sin ganancias en este período',
                    text:
                        'Los servicios completados aparecerán aquí automáticamente.',
                  )
                else ...[
                  const Text(
                    'Detalle',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...data.trips.map(
                    (trip) => _RecordCard(
                      icon: Icons.local_taxi_rounded,
                      title: 'Viaje completado',
                      subtitle:
                          _serviceMoney(
                                trip['final_fare'],
                                _tripCurrency(trip),
                              ) +
                              ' · ' +
                              _shortServiceDate(
                                trip['completed_at'] ?? trip['created_at'],
                              ),
                    ),
                  ),
                  ...data.deliveries.map(
                    (delivery) => _RecordCard(
                      icon: Icons.local_shipping_rounded,
                      title: 'Delivery entregado',
                      subtitle:
                          _serviceMoney(
                                delivery['proposed_fare'],
                                delivery['currency'],
                              ) +
                              ' · ' +
                              _shortServiceDate(
                                delivery['completed_at'] ??
                                    delivery['created_at'],
                              ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EarningsPeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _EarningsPeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        label: Text(label),
        selectedColor: const Color(0xFFEAF2FF),
        side: BorderSide(
          color: selected ? _blue : const Color(0xFFE4E7EC),
        ),
        labelStyle: TextStyle(
          color: selected ? _blue : _muted,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

class _EarningMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Map<String, num> amounts;
  final int count;
  final String defaultCurrency;

  const _EarningMetric({
    required this.icon,
    required this.label,
    required this.amounts,
    required this.count,
    required this.defaultCurrency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _blue),
          const SizedBox(height: 8),
          Text(
            _moneyTotalsLabel(
              amounts,
              fallbackCurrency: defaultCurrency,
            ),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '$count $label',
            style: TextStyle(
              color: _experienceMuted(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

String _shortServiceDate(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (date == null) return '—';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month · $hour:$minute';
}

class _SavedAddressesPage extends StatefulWidget {
  final ExpressService service;
  const _SavedAddressesPage({required this.service});
  @override
  State<_SavedAddressesPage> createState() => _SavedAddressesPageState();
}

class _SavedAddressesPageState extends State<_SavedAddressesPage> {
  int refresh = 0;

  Future<void> add() async {
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationPickerPage(
          title: 'Guardar dirección',
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final labelController = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nombre de la dirección'),
        content: TextField(
          controller: labelController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Ej. Casa, Trabajo',
            helperText: picked.label,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    final label = labelController.text.trim();
    labelController.dispose();
    if (save != true || label.isEmpty || !mounted) return;

    try {
      await widget.service.addSavedAddress(
        label: label,
        address: picked.label,
        latitude: picked.latitude,
        longitude: picked.longitude,
      );
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  Future<void> remove(Map<String, dynamic> row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar dirección'),
        content: Text(
          '¿Eliminar ${row['label'] ?? 'esta dirección'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await widget.service.deleteSavedAddress(row['id'].toString());
    if (mounted) setState(() => refresh++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mis direcciones')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: add,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Agregar'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(refresh),
          future: widget.service.savedAddresses(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return const Center(
                child: Text('Todavía no tienes direcciones guardadas.'),
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: rows
                  .map(
                    (row) => ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.location_on_outlined),
                      ),
                      title: Text(row['label'].toString()),
                      subtitle: Text(row['address'].toString()),
                      trailing: IconButton(
                        tooltip: 'Eliminar',
                        onPressed: () => remove(row),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
}

class _SafetyPage extends StatefulWidget {
  final ExpressService service;
  const _SafetyPage({required this.service});
  @override
  State<_SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends State<_SafetyPage> {
  int refresh = 0;
  Future<void> addContact() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contacto de confianza'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
            await widget.service.addTrustedContact(name: name.text.trim(), phone: phone.text.trim());
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (mounted) setState(() => refresh++);
          }, child: const Text('Guardar')),
        ],
      ),
    );
  }

  Future<void> sos() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activar SOS'),
        content: const Text(
          'Se registrará una alerta de emergencia y, si tienes un servicio activo, quedará vinculada al Viaje o Delivery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Activar SOS'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      String? tripId;
      String? deliveryId;
      double? latitude;
      double? longitude;

      final trips = await widget.service.myTrips();
      for (final trip in trips) {
        final status = trip['status']?.toString();
        if (!['completed', 'cancelled'].contains(status)) {
          tripId = trip['id']?.toString();
          break;
        }
      }

      if (tripId == null) {
        final deliveries = await widget.service.myDeliveries();
        for (final delivery in deliveries) {
          final status = delivery['status']?.toString();
          if (!['delivered', 'cancelled'].contains(status) &&
              delivery['courier_id'] != null) {
            deliveryId = delivery['id']?.toString();
            break;
          }
        }
      }

      try {
        final position =
            await const ExpressLocationService().currentPosition();
        latitude = position.latitude;
        longitude = position.longitude;
      } catch (_) {
        // El SOS sigue funcionando incluso si no hay GPS disponible.
      }

      await widget.service.createEmergency(
        tripId: tripId,
        deliveryId: deliveryId,
        latitude: latitude,
        longitude: longitude,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alerta SOS registrada y enviada al sistema.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar la alerta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seguridad')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(refresh),
      future: widget.service.trustedContacts(),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            FilledButton.icon(onPressed: sos, style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(56)), icon: const Icon(Icons.sos_rounded), label: const Text('Activar SOS')),
            const SizedBox(height: 20),
            Row(children: [const Expanded(child: Text('Contactos de confianza', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), IconButton(onPressed: addContact, icon: const Icon(Icons.person_add_alt_1_rounded))]),
            if (snapshot.connectionState == ConnectionState.waiting) const Center(child: CircularProgressIndicator()),
            if (rows.isEmpty && snapshot.connectionState != ConnectionState.waiting) const Text('Todavía no tienes contactos guardados.'),
            ...rows.map((row) => ListTile(leading: const Icon(Icons.contact_phone_outlined), title: Text(row['name'].toString()), subtitle: Text(row['phone'].toString()))),
          ],
        );
      },
    ),
  );
}

class _ActivityBundle {
  final List<Map<String, dynamic>> rides;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> deliveries;
  _ActivityBundle(this.rides, this.trips, this.deliveries);
}

class _DriverBundle {
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> rides;
  final List<Map<String, dynamic>> deliveries;
  _DriverBundle(this.profile, this.rides, this.deliveries);
}

class _ActiveBundle {
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> deliveries;
  _ActiveBundle(this.trips, this.deliveries);
}

class _EarningsBundle {
  final Map<String, num> totals;
  final Map<String, int> currencyCounts;
  final int count;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> deliveries;
  final String defaultCurrency;

  const _EarningsBundle({
    required this.totals,
    required this.currencyCounts,
    required this.count,
    required this.trips,
    required this.deliveries,
    required this.defaultCurrency,
  });
}

class _TopBrand extends StatelessWidget {
  final String role;
  const _TopBrand({required this.role});
  @override
  Widget build(BuildContext context) => Row(children: [
    const ExpressOfficialLogo(size: 44, radius: 14),
    const SizedBox(width: 10),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('EXPRESS', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        Text('Viajes', style: TextStyle(color: _experienceMuted(context), fontSize: 11)),
      ],
    ),
    const Spacer(),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _experienceDark(context)
            ? const Color(0xFF17315E)
            : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role,
        style: TextStyle(
          color: _experienceDark(context) ? const Color(0xFF9BC3FF) : _blue,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  ]);
}

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback onTap;
  final bool dark;
  const _ServiceCard({required this.icon, required this.title, required this.subtitle, required this.button, required this.onTap, this.dark = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: _cardDecoration(context),
    child: Row(children: [
      Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: _experienceDark(context)
              ? const Color(0xFF17315E)
              : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: dark ? _blueDark : _blue, size: 36),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: _experienceMuted(context))),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(backgroundColor: dark ? _blueDark : _blue),
              child: Text(button),
            ),
          ],
        ),
      ),
    ]),
  );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _InfoCard({required this.icon, required this.title, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(context),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(text, style: TextStyle(color: _experienceMuted(context))),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RecordCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final VoidCallback? onTap;

  const _RecordCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              padding: const EdgeInsets.all(15),
              decoration: _cardDecoration(context),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _experienceDark(context)
                        ? const Color(0xFF17315E)
                        : const Color(0xFFEAF2FF),
                    child: Icon(icon, color: _blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: _experienceMuted(context),
                            fontSize: 12,
                          ),
                        ),
                        if (onTap != null) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Toca para ver detalles',
                            style: TextStyle(
                              color: _blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(width: 8),
                    action!,
                  ] else if (onTap != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _muted,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _JobCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback onTap;
  const _JobCard({required this.icon, required this.title, required this.subtitle, required this.button, required this.onTap});
  @override
  Widget build(BuildContext context) => _RecordCard(icon: icon, title: title, subtitle: subtitle, action: FilledButton(onPressed: onTap, child: Text(button)));
}

class _ErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline_rounded, size: 44), const SizedBox(height: 10), Text('Error: $error', textAlign: TextAlign.center), const SizedBox(height: 14), FilledButton(onPressed: onRetry, child: const Text('Reintentar'))])));
}

BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
  color: _experienceSurface(context),
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: _experienceBorder(context)),
  boxShadow: [
    BoxShadow(
      color: _experienceDark(context)
          ? const Color(0x66000000)
          : const Color(0x0D000000),
      blurRadius: 18,
      offset: const Offset(0, 7),
    ),
  ],
);

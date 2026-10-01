import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:terminate_restart/terminate_restart.dart';

import 'core/supabase_client.dart';
import 'location_service.dart';
import 'preview_diagnostics_hub.dart';
import 'push_notifications.dart';

class ExpressPreviewOverlay extends StatelessWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const ExpressPreviewOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          right: 12,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: FloatingActionButton.small(
                heroTag: 'express-preview-diagnostics',
                tooltip: 'Diagnóstico Express Preview',
                onPressed: () => _openDiagnostics(context),
                child: const Icon(Icons.bug_report_rounded),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 8,
          child: const SafeArea(
            child: _PreviewUpdateButton(),
          ),
        ),
        Positioned(
          left: 10,
          bottom: MediaQuery.paddingOf(context).bottom + 8,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Text(
                  'EXPRESS PREVIEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openDiagnostics(BuildContext context) async {
    final navigator = navigatorKey.currentState;
    final overlayContext = navigator?.overlay?.context;
    if (overlayContext == null) return;

    await showModalBottomSheet<void>(
      context: overlayContext,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const FractionallySizedBox(
        heightFactor: .88,
        child: _PreviewDiagnosticsPanel(),
      ),
    );
  }
}

class _PreviewUpdateButton extends StatefulWidget {
  const _PreviewUpdateButton();

  @override
  State<_PreviewUpdateButton> createState() => _PreviewUpdateButtonState();
}

class _PreviewUpdateButtonState extends State<_PreviewUpdateButton> {
  final ShorebirdUpdater updater = ShorebirdUpdater();
  bool busy = false;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _restartToApply() async {
    _notify('Cambios listos. Reiniciando Express Preview…');
    await Future<void>.delayed(const Duration(milliseconds: 650));
    await TerminateRestart.instance.restartApp(
      options: const TerminateRestartOptions(
        terminate: true,
        clearData: false,
      ),
    );
  }

  Future<void> _updateChanges() async {
    if (busy) return;

    setState(() => busy = true);
    try {
      if (!updater.isAvailable) {
        _notify('Shorebird no está disponible en esta compilación.');
        return;
      }

      final status = await updater.checkForUpdate();
      if (!mounted) return;

      switch (status) {
        case UpdateStatus.upToDate:
          _notify('Express Preview ya está actualizado.');
          return;
        case UpdateStatus.outdated:
          _notify('Descargando los cambios…');
          await updater.update();
          if (!mounted) return;
          await _restartToApply();
          return;
        case UpdateStatus.restartRequired:
          await _restartToApply();
          return;
        case UpdateStatus.unavailable:
          _notify('No se pudo consultar Shorebird en este momento.');
          return;
      }
    } on UpdateException catch (e) {
      _notify('No se pudo descargar la actualización: $e');
    } catch (e) {
      _notify('Error al actualizar Express Preview: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: FilledButton.icon(
        onPressed: busy ? null : _updateChanges,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          visualDensity: VisualDensity.compact,
        ),
        icon: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.system_update_alt_rounded, size: 18),
        label: Text(busy ? 'Actualizando…' : 'Actualizar cambios'),
      ),
    );
  }
}

class _PreviewDiagnosticsPanel extends StatefulWidget {
  const _PreviewDiagnosticsPanel();

  @override
  State<_PreviewDiagnosticsPanel> createState() =>
      _PreviewDiagnosticsPanelState();
}

class _PreviewDiagnosticsPanelState
    extends State<_PreviewDiagnosticsPanel> {
  Timer? timer;
  bool loading = true;
  String? error;
  String version = '-';
  String buildNumber = '-';
  String pushState = '-';
  String? backendRideId;
  String? backendRideStatus;
  String? backendTripStatus;
  int backendHomeOfferCount = 0;
  int backendDirectOfferCount = 0;
  int recentDiagnosticCount = 0;
  int recentFailureCount = 0;
  String? lastDiagnostic;
  String? gpsStatus;
  DateTime? refreshedAt;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refresh(silent: true)),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Map<String, dynamic>? _mapOrNull(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => loading = true);

    try {
      final info = await PackageInfo.fromPlatform();
      final raw = await supabase.rpc('passenger_home_state');
      final state = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      final openRide = _mapOrNull(state['open_ride']);
      final activeTrip = _mapOrNull(state['active_trip']);
      final offersRaw = state['offers'];
      final homeOffers = offersRaw is List ? offersRaw.length : 0;

      var directOffers = 0;
      final rideId = openRide?['id']?.toString();
      if (rideId != null && rideId.isNotEmpty) {
        final direct = await supabase.rpc(
          'passenger_pending_ride_offers',
          params: {'p_ride_request_id': rideId},
        );
        directOffers = direct is List ? direct.length : 0;
      }

      final permission = await pushPermissionState();

      final diagnosticRows = await supabase
          .from('app_error_logs')
          .select('level,event_name,message,source,created_at')
          .order('created_at', ascending: false)
          .limit(12);
      final diagnostics = List<Map<String, dynamic>>.from(diagnosticRows);
      final failures = diagnostics.where((row) {
        final level = row['level']?.toString();
        return level == 'warning' || level == 'error' || level == 'fatal';
      }).length;
      final latest = diagnostics.isEmpty ? null : diagnostics.first;
      final latestLabel = latest == null
          ? null
          : [
              latest['level']?.toString().toUpperCase(),
              latest['event_name']?.toString() ?? latest['source']?.toString(),
              latest['message']?.toString(),
            ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');

      if (!mounted) return;
      setState(() {
        version = info.version;
        buildNumber = info.buildNumber;
        pushState = permission;
        backendRideId = rideId;
        backendRideStatus = openRide?['status']?.toString();
        backendTripStatus = activeTrip?['status']?.toString();
        backendHomeOfferCount = homeOffers;
        backendDirectOfferCount = directOffers;
        recentDiagnosticCount = diagnostics.length;
        recentFailureCount = failures;
        lastDiagnostic = latestLabel;
        refreshedAt = DateTime.now().toUtc();
        error = null;
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

  Future<void> _testGps() async {
    setState(() => gpsStatus = 'Consultando GPS…');
    try {
      final position = await const ExpressLocationService().currentPosition();
      if (!mounted) return;
      setState(() {
        gpsStatus =
            '${position.latitude.toStringAsFixed(6)}, '
            '${position.longitude.toStringAsFixed(6)} · '
            '±${position.accuracy.toStringAsFixed(0)} m';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => gpsStatus = 'Error: $e');
    }
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PreviewPassengerUiSnapshot>(
      valueListenable: PreviewDiagnosticsHub.passengerUi,
      builder: (context, ui, _) {
        final mismatch =
            backendDirectOfferCount > 0 && ui.uiOfferCount == 0;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Express Preview · Diagnóstico'),
            actions: [
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => _refresh(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _row('APK Preview', 'v$version · build $buildNumber'),
                      _row(
                        'Usuario',
                        supabase.auth.currentUser?.id ?? 'sin sesión',
                      ),
                      _row('Push', pushState),
                      _row(
                        'Actualizado',
                        refreshedAt?.toIso8601String() ?? '-',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _row('Backend ride', backendRideId ?? 'ninguno'),
                      _row('Ride status', backendRideStatus ?? '-'),
                      _row('Trip status', backendTripStatus ?? '-'),
                      _row(
                        'Ofertas home RPC',
                        backendHomeOfferCount.toString(),
                      ),
                      _row(
                        'Ofertas directas',
                        backendDirectOfferCount.toString(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _row(
                        'Diagnósticos recientes',
                        recentDiagnosticCount.toString(),
                      ),
                      _row(
                        'Fallos/alertas',
                        recentFailureCount.toString(),
                        valueColor: recentFailureCount > 0
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      _row(
                        'Último diagnóstico',
                        lastDiagnostic ?? 'ninguno',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                color: mismatch
                    ? Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withValues(alpha: .45)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _row('UI openRide', ui.openRideId ?? 'ninguno'),
                      _row('UI ofertas', ui.uiOfferCount.toString()),
                      _row(
                        'Panel búsqueda',
                        ui.searchPanelMounted ? 'MONTADO' : 'no',
                      ),
                      _row(
                        'OffersCard',
                        ui.offersCardMounted ? 'MONTADO' : 'no',
                      ),
                      _row('loadRevision', ui.loadRevision.toString()),
                      _row('panelRevision', ui.panelRevision.toString()),
                      _row('Último evento', ui.lastEvent),
                      if (mismatch)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'ALERTA: el backend tiene ofertas pero la UI no. '
                            'Este es exactamente el fallo de presentación.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _testGps,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Probar GPS nativo'),
              ),
              if (gpsStatus != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  gpsStatus!,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

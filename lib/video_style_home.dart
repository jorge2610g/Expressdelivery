Warning: truncated output (original token count: 164157)
Total output lines: 18603

import 'cancellation_fee_confirmation.dart';
import 'express_offline_banner.dart';
import 'offline_status.dart';
import 'driver_floating_offers.dart';
import 'driver_floating_offer_focus.dart';
import 'driver_floating_offer_data.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_error_reporter.dart';
import 'core/supabase_client.dart';
import 'core/runtime_channel.dart';
import 'connected_center.dart';
import 'driver_focus_navigation.dart';
import 'driver_realtime_scope.dart';
import 'driver_priority_page.dart';
import 'driver_championship_page.dart';
import 'driver_championship_visibility.dart';
import 'express_marketplace_page.dart';
import 'core/driver_work_scope.dart';
import 'express_branding.dart';
import 'express_journey_dialog.dart';
import 'location_picker.dart';
import 'location_service.dart';
import 'map_provider.dart';
import 'push_notifications.dart';
import 'express_diagnostics_hub.dart';
import 'private_voice_call.dart';
import 'passenger_ride_currency.dart';
import 'route_confirmation_sheet_fraction.dart';
import 'driver_offer_amount_dialog.dart';
import 'pickup_wait_countdown.dart';
import 'map_visible_camera.dart';
import 'passenger_trip_guard.dart';
import 'ride_offer_error_messages.dart';
import 'express_publish_loader.dart';
import 'passenger_service_presentation.dart';
import 'service_tracking.dart';
import 'driver_registration_gate.dart';
import 'driver_portrait.dart';
import 'driver_online_sequence.dart';
import 'services/express_service.dart';
import 'passenger_search_fare_step.dart';
import 'call_preferences_page.dart';
import 'driver_permissions_page.dart';
import 'call_overlay_sync.dart';
import 'call_presence.dart';

const Color expressBlue = Color(0xFF0B57D0);
const Color expressDark = Color(0xFF101828);
const Color expressMuted = Color(0xFF667085);
const LatLng expressFallback = LatLng(-14.8333, -64.9000);
const bool expressPreviewDemandMode = bool.fromEnvironment(
  'EXPRESS_PREVIEW_MODE',
  defaultValue: false,
);

const List<Map<String, dynamic>> _fallbackRideServices = [
  {
    'service_key': 'motorcycle',
    'name': 'Moto',
    'description': 'Servicio en moto disponible en Trinidad',
    'vehicle_type': 'motorcycle',
    'enabled': true,
    'allow_bidding': true,
    'allow_fixed_price': true,
  },
];

IconData _rideServiceIcon(Map<String, dynamic> service) {
  final key = service['service_key']?.toString();
  if (key == 'parcel') return Icons.inventory_2_outlined;
  if (key == 'carga') return Icons.local_shipping_rounded;
  final vehicle = service['vehicle_type']?.toString();
  if (key == 'xl' || vehicle == 'xl') return Icons.airport_shuttle_rounded;
  if (vehicle == 'motorcycle' || key == 'motorcycle') {
    return Icons.two_wheeler_rounded;
  }
  if (key == 'comfort') return Icons.local_taxi_rounded;
  if (vehicle == 'any') return Icons.commute_rounded;
  return Icons.directions_car_filled_rounded;
}

int _rideServiceSeats(Map<String, dynamic> service) {
  final key = service['service_key']?.toString();
  final vehicle = service['vehicle_type']?.toString();
  if (key == 'xl' || vehicle == 'xl') return 6;
  if (vehicle == 'motorcycle' || key == 'motorcycle') return 1;
  return 4;
}

Future<List<LatLng>> _expressRoadRoute(LatLng from, LatLng to) async {
  final fallback = <LatLng>[from, to];
  try {
    final route = await ExpressMapProvider.drivingRoute(
      from: from,
      to: to,
    );
    return route.points.length >= 2 ? route.points : fallback;
  } catch (_) {
    return fallback;
  }
}

double? asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _zoneMoneyPrefix(String? raw) {
  final code = (raw ?? 'BOB').toUpperCase();
  if (code == 'BOB') return 'Bs';
  if (code == 'CLP') return r'$';
  return code;
}

String _rideMoney(Object? amount, Object? rawCurrency) {
  final code = (rawCurrency?.toString() ?? 'BOB').toUpperCase();
  final value = asDouble(amount);
  if (value == null) return _zoneMoneyPrefix(code) + ' -';

  if (code == 'CLP') {
    final digits = value.round().abs().toString();
    final reversed = digits.split('').reversed.toList();
    final grouped = <String>[];
    for (var i = 0; i < reversed.length; i++) {
      if (i > 0 && i % 3 == 0) grouped.add('.');
      grouped.add(reversed[i]);
    }
    final formatted = grouped.reversed.join();
    return _zoneMoneyPrefix(code) +
        ' ' +
        (value < 0 ? '-' : '') +
        formatted;
  }

  final decimals = value == value.roundToDouble() ? 0 : 2;
  return _zoneMoneyPrefix(code) + ' ' + value.toStringAsFixed(decimals);
}

double _expressMapMarkerScale(double zoom) {
  return ((zoom - 10.5) / 4.5).clamp(.44, 1.0).toDouble();
}


bool _isExpressPlaceholderAddress(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return true;
  final normalized = text.toLowerCase();
  return normalized == 'origen' ||
      normalized == 'destino' ||
      normalized == 'mi ubicación' ||
      normalized == 'mi ubicacion' ||
      normalized == 'mi ubicación actual' ||
      normalized == 'mi ubicacion actual' ||
      normalized == 'ubicación seleccionada' ||
      normalized == 'ubicacion seleccionada' ||
      normalized == 'punto seleccionado' ||
      normalized.contains('buscando dirección') ||
      normalized.contains('buscando direccion');
}

String _expressDriverRouteLabel(
  Map<String, dynamic> route, {
  required String addressKey,
  required String latitudeKey,
  required String longitudeKey,
  required String fallback,
}) {
  final raw = route[addressKey]?.toString().trim();
  if (!_isExpressPlaceholderAddress(raw)) return raw!;
  final lat = asDouble(route[latitudeKey]);
  final lng = asDouble(route[longitudeKey]);
  if (lat != null && lng != null) {
    return '$fallback · ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }
  return fallback;
}

Future<String?> _expressReverseGeocodeAddress(LatLng point) async {
  try {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'jsonv2',
        'zoom': '18',
        'addressdetails': '1',
      },
    );
    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'ExpressDelivery/1.0',
        'Accept-Language': 'es',
      },
    ).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final label = decoded['display_name']?.toString().trim();
    return label == null || label.isEmpty ? null : label;
  } catch (_) {
    return null;
  }
}

enum _ExpressTransitionPhase { working, success, error }

class _ExpressTransitionView {
  final _ExpressTransitionPhase phase;
  final String title;
  final String? subtitle;

  const _ExpressTransitionView({
    required this.phase,
    required this.title,
    this.subtitle,
  });
}

/// Bloquea una acción crítica sin conexión: muestra un aviso discreto y no
/// envía nada. Nunca se confirma un viaje, pago o pedido sin respuesta válida
/// del servidor.
bool _expressOfflineBlocked(BuildContext context) {
  if (ExpressConnectivityMonitor.instance.isOnline) return false;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
    content: Text('Sin conexión. Esta acción se habilita al recuperar internet.'),
  ));
  return true;
}

/// Lectura ligera y de solo lectura: basta para comprobar que hay conexión.
Future<void> _expressConnectivityProbe(ExpressService service) async {
  await service.passengerActiveTripLiveState();
}

Future<T> runExpressStateTransition<T>(
  BuildContext context, {
  required String processingTitle,
  required String successTitle,
  String? processingSubtitle,
  String? successSubtitle,
  required String eventName,
  required Future<T> Function() action,
  FutureOr<void> Function(T result)? onSuccess,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final state = ValueNotifier<_ExpressTransitionView>(
    _ExpressTransitionView(
      phase: _ExpressTransitionPhase.working,
      title: processingTitle,
      subtitle: processingSubtitle,
    ),
  );

  final entry = OverlayEntry(
    builder: (overlayContext) => ValueListenableBuilder<_ExpressTransitionView>(
      valueListenable: state,
      builder: (context, view, _) => _ExpressTransitionOverlay(view: view),
    ),
  );

  overlay.insert(entry);
  await Future<void>.delayed(const Duration(milliseconds: 16));

  try {
    final result = await action();
    if (onSuccess != null) {
      await onSuccess(result);
    }
    state.value = _ExpressTransitionView(
      phase: _ExpressTransitionPhase.success,
      title: successTitle,
      subtitle: successSubtitle,
    );
    unawaited(HapticFeedback.mediumImpact());
    unawaited(
      AppErrorReporter.event(
        eventName,
        source: 'ride_state_transition',
        screen: 'ride_flow',
        context: {'result': 'success'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return result;
  } catch (error, stack) {
    state.value = const _ExpressTransitionView(
      phase: _ExpressTransitionPhase.error,
      title: 'No se pudo completar',
      subtitle: 'Revisa la conexión e inténtalo nuevamente.',
    );
    unawaited(HapticFeedback.heavyImpact());
    unawaited(
      AppErrorReporter.capture(
        error,
        stack,
        source: 'ride_state_transition',
        screen: 'ride_flow',
        eventName: eventName + '_FAILED',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 850));
    rethrow;
  } finally {
    if (entry.mounted) entry.remove();
    state.dispose();
  }
}

class _ExpressTransitionOverlay extends StatelessWidget {
  final _ExpressTransitionView view;

  const _ExpressTransitionOverlay({required this.view});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final surface = dark ? const Color(0xFF171717) : Colors.white;
    final text = dark ? Colors.white : expressDark;
    final muted = dark ? const Color(0xFFB0B6C2) : expressMuted;
    final success = view.phase == _ExpressTransitionPhase.success;
    final failed = view.phase == _ExpressTransitionPhase.error;

    // Indicador discreto arriba: no oscurece el mapa ni absorbe toques. El
    // botón que originó la acción ya se bloquea con sus propias banderas.
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TweenAnimationBuilder<double>(
          tween: Tween(begin: .92, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            child: Opacity(opacity: scale.clamp(0.0, 1.0), child: child),
          ),
          child: Container(
            width: 286,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: success
                      ? Container(
                          key: const ValueKey('success'),
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Color(0xFF12B76A),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        )
                      : failed
                          ? Container(
                              key: const ValueKey('error'),
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD92D20),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('working'),
                              width: 58,
                              height: 58,
                              child: CircularProgressIndicator(
                                strokeWidth: 5,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    view.title,
                    key: ValueKey(view.title),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: text,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (view.subtitle != null && view.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    view.subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: muted,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
            ),
          ),
        ),
      ),
    );
  }
}

void showExpressStateBanner(
  BuildContext context, {
  required String title,
  required String subtitle,
  required IconData icon,
  required String eventName,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      final top = MediaQuery.paddingOf(overlayContext).top + 14;
      return Positioned(
        top: top,
        left: 18,
        right: 18,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            builder: (context, value, child) => Transform.translate(
              offset: Offset(0, -26 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF101828),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: expressBlue.withValues(alpha: .24),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFFD0D5DD),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  unawaited(HapticFeedback.selectionClick());
  unawaited(
    AppErrorReporter.event(
      eventName,
      source: 'ride_state_banner',
      screen: 'ride_flow',
    ),
  );
  Timer(const Duration(milliseconds: 2400), () {
    if (entry.mounted) entry.remove();
  });
}

Future<void> callExpressNumber(
  BuildContext context,
  String? phone,
) async {
  final value = phone?.trim();
  if (value == null || value.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay teléfono disponible.')),
    );
    return;
  }

  final uri = Uri(scheme: 'tel', path: value);
  final opened = await launchUrl(uri);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir la llamada.')),
    );
  }
}

Future<void> shareExpressTrip(
  BuildContext context,
  ExpressService service,
  Map<String, dynamic> trip,
  Map<String, dynamic>? driver,
  Map<String, dynamic>? vehicle,
) async {
  final ride = trip['ride_requests'] is Map
      ? Map<String, dynamic>.from(trip['ride_requests'] as Map)
      : <String, dynamic>{};
  final driverName = driver?['full_name']?.toString().trim();
  final plate = vehicle?['plate']?.toString().trim();
  final modelParts = [
    vehicle?['brand']?.toString().trim(),
    vehicle?['model']?.toString().trim(),
  ].whereType<String>().where((value) => value.isNotEmpty).toList();

  String shareUrl;
  try {
    shareUrl = await service.createTripShareLink(trip['id'].toString());
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se pudo crear el enlace del viaje: $error'),
      ),
    );
    return;
  }

  final text = [
    'Estoy viajando con Express.',
    if (driverName != null && driverName.isNotEmpty)
      'Conductor: $driverName.',
    if (modelParts.isNotEmpty) 'Vehículo: ${modelParts.join(' ')}.',
    if (plate != null && plate.isNotEmpty) 'Patente: $plate.',
    if (ride['pickup_address'] != null)
      'Origen: ${ride['pickup_address']}.',
    if (ride['destination_address'] != null)
      'Destino: ${ride['destination_address']}.',
    'Sigue el viaje en tiempo real: $shareUrl',
    'El enlace se desactiva cuando el viaje termina.',
  ].join(' ');

  final uri = Uri.https('wa.me', '/', {'text': text});
  try {
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (opened) return;
  } catch (_) {}

  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo abrir WhatsApp. El enlace del viaje se copió.',
        ),
      ),
    );
  }
}

Future<void> raiseExpressTripEmergency(
  BuildContext context,
  ExpressService service,
  String tripId,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Activar alerta SOS'),
      content: const Text(
        'Se registrará una alerta de emergencia asociada a este viaje.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Volver'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          icon: const Icon(Icons.sos_rounded),
          label: const Text('Activar SOS'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    await service.createEmergency(tripId: tripId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Alerta SOS registrada y enviada al sistema.'),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo registrar la alerta: $e')),
    );
  }
}

Future<String?> askExpressCancellationReason(
  BuildContext context,
  String serviceLabel,
) async {
  const reasons = [
    'Cambié de planes',
    'El tiempo de espera es muy largo',
    'Elegí mal el origen o destino',
    'Problema con la tarifa',
    'Otro motivo',
  ];

  String? selected;
  final controller = TextEditingController();

  final result = await showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final dark = _riderHomeDark(sheetContext);
      final surface = dark ? const Color(0xFF171717) : Colors.white;
      final soft = dark ? const Color(0xFF222222) : const Color(0xFFF8FAFC);
      final text = dark ? Colors.white : expressDark;
      final muted = dark ? const Color(0xFF9CA3AF) : expressMuted;
      final border =
          dark ? const Color(0xFF363636) : const Color(0xFFD0D5DD);

      return StatefulBuilder(
        builder: (context, setLocalState) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Cancelar $serviceLabel',
                              style: TextStyle(
                                color: text,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: Icon(Icons.close_rounded, color: text),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Puedes cancelar ahora. El motivo es opcional.',
                          style: TextStyle(
                            color: muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .42,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final reason in reasons)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: selected == reason
                                        ? expressBlue.withValues(alpha: .12)
                                        : soft,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected == reason
                                          ? expressBlue
                                          : border,
                                    ),
                                  ),
                                  child: RadioListTile<String>(
                                    dense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    value: reason,
                                    groupValue: selected,
                                    activeColor: expressBlue,
                                    title: Text(
                                      reason,
                                      style: TextStyle(
                                        color: text,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setLocalState(() => selected = value);
                                    },
                                  ),
                                ),
                              if (selected == 'Otro motivo') ...[
                                const SizedBox(height: 2),
                                TextField(
                                  controller: controller,
                                  maxLines: 3,
                                  style: TextStyle(color: text),
                                  decoration: InputDecoration(
                                    hintText: 'Escribe el motivo (opcional)',
                                    hintStyle: TextStyle(color: muted),
                                    filled: true,
                                    fillColor: soft,
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: border),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(
                                        color: expressBlue,
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              child: const Text('Seguir viaje'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                final custom = controller.text.trim();
                                final reason = selected == 'Otro motivo' &&
                                        custom.isNotEmpty
                                    ? custom
                                    : selected ?? 'Cancelado por el pasajero';
                                Navigator.pop(sheetContext, reason);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFD92D20),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('Cancelar ahora'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  controller.dispose();
  return result;
}

Future<bool> showExpressRatingDialog(
  BuildContext context,
  ExpressService service,
  Map<String, dynamic> pending, {
  required String counterpartLabel,
}) async {
  final kind = pending['kind']?.toString() ?? 'trip';
  final toUserId = pending['to_user_id']?.toString();
  if (toUserId == null || toUserId.isEmpty) return false;
  final label = kind == 'delivery' ? 'repartidor' : counterpartLabel;

  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ExpressRatingDialog(
      service: service,
      pending: pending,
      toUserId: toUserId,
      title: 'Califica al $label',
    ),
  );
  return saved == true;
}

/// Diálogo de calificación. Su controlador de comentario vive en el State y se
/// libera en dispose(), cuando la ruta ya cerró; liberarlo justo después de
/// `await showDialog` dejaba el TextField usando un controlador descartado.
class _ExpressRatingDialog extends StatefulWidget {
  const _ExpressRatingDialog({
    required this.service,
    required this.pending,
    required this.toUserId,
    required this.title,
  });

  final ExpressService service;
  final Map<String, dynamic> pending;
  final String toUserId;
  final String title;

  @override
  State<_ExpressRatingDialog> createState() => _ExpressRatingDialogState();
}

class _ExpressRatingDialogState extends State<_ExpressRatingDialog> {
  int _score = 5;
  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_expressOfflineBlocked(context)) return;
    final kind = widget.pending['kind']?.toString() ?? 'trip';
    final comment = _comment.text.trim();
    try {
      await widget.service.submitRating(
        tripId: kind == 'trip' ? widget.pending['id']?.toString() : null,
        deliveryId:
            kind == 'delivery' ? widget.pending['id']?.toString() : null,
        toUserId: widget.toUserId,
        score: _score,
        comment: comment.isEmpty ? null : comment,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la calificación: ' + e.toString()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'La calificación es privada: la otra persona no verá quién la envió y no recibirá un push.',
              textAlign: TextAlign.center,
              style: TextStyle(color: expressMuted),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final value = index + 1;
                return IconButton(
                  tooltip: value.toString(),
                  onPressed: () => setState(() => _score = value),
                  icon: Icon(
                    value <= _score
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFF5A623),
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Comentario opcional',
                hintText: 'Cuéntanos cómo fue el servicio',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Después'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.star_rounded),
          label: const Text('Enviar calificación'),
        ),
      ],
    );
  }
}

double _routeConfirmationSheetFraction(
  BuildContext context, {
  bool hasPendingRating = false,
}) {
  final media = MediaQuery.of(context);
  final usesGestureNavigation = media.systemGestureInsets.bottom > 0;
  // Classic Android 3-button navigation receives extra room; gesture
  // navigation and web stay visually tighter to the bottom edge.
  final classicNavigationInset = usesGestureNavigation
      ? 0.0
      : media.viewPadding.bottom.clamp(0.0, 56.0).toDouble();
  return routeConfirmationSheetFraction(
    height: media.size.height,
    classicNavigationInset: classicNavigationInset,
    hasPendingRating: hasPendingRating,
  );
}

double _routeConfirmationBottomPadding(BuildContext context) {
  final media = MediaQuery.of(context);
  final usesGestureNavigation = media.systemGestureInsets.bottom > 0;

  if (usesGestureNavigation) return 8;

  return 8 + media.viewPadding.bottom.clamp(0.0, 56.0).toDouble();
}

double _passengerHomeSheetFraction(BuildContext context) {
  final media = MediaQuery.of(context);
  final height = media.size.height;
  if (height <= 0) return .38;

  final desiredHeight =
      315.0 + media.viewPadding.bottom.clamp(0.0, 32.0).toDouble();
  return (desiredHeight / height).clamp(.35, .41).toDouble();
}

double _rideChooserSheetFraction(BuildContext context) {
  final media = MediaQuery.of(context);
  final height = media.size.height;
  if (height <= 0) return .62;

  final usesGestureNavigation = media.systemGestureInsets.bottom > 0;
  final classicNavigationInset = usesGestureNavigation
      ? 0.0
      : media.viewPadding.bottom.clamp(0.0, 56.0).toDouble();

  // This sheet is intentionally static. The five service slots fit in one
  // compact row, so no vertical service list or extra drag room is needed.
  final desiredHeight = 505.0 + classicNavigationInset;
  return (desiredHeight / height).clamp(.56, .72).toDouble();
}

class PassengerMapHome extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic>? initialState;
  final Map<String, dynamic>? initialZone;
  final String initialServiceType;
  final bool openDestinationPickerOnStart;
  // Se llama una sola vez al abrir el selector de entrada rápida. Sin esto, el
  // indicador queda en true y el selector vuelve a abrirse cada vez que el
  // mapa se reconstruye (p. ej. al llegar la oferta del conductor).
  final VoidCallback? onDestinationPickerOpened;
  final VoidCallback onChanged;
  final VoidCallback onHardReset;
  final VoidCallback onSwitchMode;
  final VoidCallback onOpenMarket;
  final VoidCallback onHistory;
  final VoidCallback onScheduledTrips;
  final VoidCallback onPayments;
  final VoidCallback onProfile;
  final VoidCallback onSavedPlaces;
  final VoidCallback onSafety;
  final ValueChanged<bool>? onFlowStateChanged;
  final ValueChanged<bool>? onTripNavigationLockChanged;

  const PassengerMapHome({
    super.key,
    required this.service,
    this.initialState,
    this.initialZone,
    this.initialServiceType = 'ride',
    this.openDestinationPickerOnStart = false,
    this.onDestinationPickerOpened,
    required this.onChanged,
    required this.onHardReset,
    required this.onSwitchMode,
    required this.onOpenMarket,
    required this.onHistory,
    required this.onScheduledTrips,
    required this.onPayments,
    required this.onProfile,
    required this.onSavedPlaces,
    required this.onSafety,
    this.onFlowStateChanged,
    this.onTripNavigationLockChanged,
  });

  @override
  State<PassengerMapHome> createState() => _PassengerMapHomeState();
}

class _PassengerMapHomeState extends State<PassengerMapHome>
    with WidgetsBindingObserver {
  // Sobreposición activa: muestra las opciones que dependen de ella (burbuja, ofertas emergentes, llamadas).
  bool overlayAllowed = false;
  String? overlayPromptTripId;
  final mapController = MapController();
  final sheetController = DraggableScrollableController();
  final locationService = const ExpressLocationService();
  StreamSubscription<Position>? passengerMapPositionSubscription;
  DateTime? lastPassengerCameraMoveAt;

  LatLng? current;
  PickedLocation? pickup;
  // True while the origin is the automatic GPS point ("Mi ubicación actual").
  // That point must follow the fresh fix; a manually chosen origin never does.
  bool _pickupFromGps = false;
  PickedLocation? destination;
  String serviceType = 'ride';
  bool parcelAvailable = false;
  String? parcelKind;
  final parcelSenderName = TextEditingController();
  final parcelSenderPhone = TextEditingController();
  final parcelRecipientName = TextEditingController();
  final parcelRecipientPhone = TextEditingController();
  final parcelDescription = TextEditingController();
  final ImagePicker parcelImagePicker = ImagePicker();
  final List<String> parcelPhotoPaths = [];
  bool parcelPhotosUploading = false;
  String category = 'motorcycle';
  String payment = 'cash';
  bool paymentInitializedFromProfile = false;
  num fare = 5;
  Map<String, dynamic> fareQuote = const <String, dynamic>{};
  // Increasing epoch discards older fare responses after changing service,
  // confirming a new route or navigating back. A stale CLP/BOB quote can
  // never overwrite the current selection.
  int fareQuoteEpoch = 0;
  List<Map<String, dynamic>> rideServices = _fallbackRideServices;
  Map<String, dynamic> runtimeSettings = const <String, dynamic>{};
  Map<String, dynamic>? activeZone;
  // A landing snapshot can belong to a previous country. Only a GPS/pickup
  // coordinate resolution may make the zone authoritative for this Home.
  bool zoneResolvedByCoordinates = false;
  int rideCatalogRequestEpoch = 0;
  bool zoneOutsideCoverage = false;
  DateTime? scheduledFor;
  bool locating = false;
  bool creating = false;
  bool routing = false;
  double passengerMapZoom = 14.6;
  bool? lastReportedPassengerFlowActive;
  bool? lastReportedTripNavigationLock;
  bool passengerFlowMinimized = false;
  bool quoting = false;
  bool fareManuallyEdited = false;
  bool routeConfirmed = false;
  bool autoAcceptNearest = false;
  bool autoAccepting = false;
  String? cancellingRideId;
  String? cancellingTripId;
  String? cancellingDeliveryId;
  final Set<String> locallyCancelledRideIds = <String>{};
  // Calificaciones que el pasajero acaba de guardar. Ocultan el pendiente en
  // pantalla aunque una carga en vuelo todavía traiga la versión anterior.
  final Set<String> locallyRatedPendingIds = <String>{};
  final Set<String> locallyCancelledTripIds = <String>{};
  final Set<String> locallyCancelledDeliveryIds = <String>{};
  double? routeDistanceKm;
  int? routeDurationMinutes;
  String? passengerMapTripStageKey;
  String? passengerActiveRoadRouteKey;
  List<LatLng> passengerActiveRoadRoute = const [];
  bool passengerActiveRoadRouteLoading = false;
  List<LatLng> roadRoute = const [];

  // Los marcadores cercanos no deben parpadear si una consulta puntual tarda,
  // falla o devuelve vacío mientras el backend se actualiza. Conservamos la
  // última lista válida durante una ventana corta y siempre filtrada por el
  // tipo de vehículo solicitado.
  static const Duration _nearbyDriversStaleGrace =
      Duration(seconds: 25);
  DateTime? nearbyDriversLastNonEmptyAt;
  String? nearbyDriversLastRequestedType;

  _PassengerStateData? cachedData;
  late Future<_PassengerStateData> homeFuture;
  int loadRevision = 0;
  int panelRevision = 0;
  int passengerOfferStateRevision = 0;
  Timer? timer;
  bool passengerOfferActionBusy = false;
  bool homeRefreshInFlight = false;
  bool homeRefreshQueued = false;
  Future<void>? passengerPendingRatingRefreshFuture;
  StreamSubscription<List<Map<String, dynamic>>>?
      passengerOfferRealtimeSubscription;
  StreamSubscription<String>? passengerForegroundPushSubscription;
  RealtimeChannel? zoneServiceCatalogChannel;
  String? passengerOfferRealtimeRideId;
  Timer? passengerOfferRealtimeDebounce;
  Timer? zoneServiceCatalogDebounce;
  Timer? passengerOfferBootstrapTimer;
  Timer? passengerCriticalStateTimer;
  Timer? passengerLiveOfferTimer;
  // Vigila el vencimiento de la búsqueda sin depender de un refresco: al vencer
  // se ofrecen las tres opciones antes de que el servidor retire la solicitud.
  Timer? searchRenewalWatch;
  bool passengerOfferBootstrapInFlight = false;
  bool passengerCriticalStateInFlight = false;
  bool passengerLiveOfferInFlight = false;
  bool passengerLiveOfferStateReady = false;
  Map<String, dynamic>? passengerLiveOfferRide;
  List<Map<String, dynamic>> passengerLiveOffers =
      <Map<String, dynamic>>[];
  bool passengerOfferPresentationActive = false;
  int passengerOfferPresentationEpoch = 0;
  final Set<String> locallyExpiredPassengerOfferKeys = <String>{};
  List<Map<String, dynamic>> passengerOfferOverlayOffers =
      <Map<String, dynamic>>[];
  Map<String, dynamic>? passengerOfferOverlayRide;
  String? passengerOfferOverlayRideId;
  final Set<String> renewalPromptedRideIds = <String>{};
  bool renewalDecisionOpen = false;
  String? renewalDecisionRideId;
  String? lastAnimatedPassengerTripId;
  String? lastAnimatedPassengerTripStatus;
  String? lastAnimatedPassengerCompletedTripId;

  @override
  void initState() {
    ExpressConnectivityMonitor.instance.probe =
        () => _expressConnectivityProbe(widget.service);
    ExpressConnectivityMonitor.instance.addListener(_onConnectivityChanged);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ExpressCallPresence.start(widget.service);
      if (widget is DriverMapHome) unawaited(syncDriverPushOverlayState(widget.service));
      unawaited(syncOverlayCallPreference(widget.service).then((granted) {
        if (mounted) setState(() => overlayAllowed = granted);
      }));
      // La sugerencia de sobreposición aparece al empezar un viaje, no al abrir la app.
    });
    serviceType = widget.initialServiceType == 'delivery' ? 'delivery' : 'ride';
    if (widget.initialZone != null && widget.initialZone!.isNotEmpty) {
      activeZone = Map<String, dynamic>.from(widget.initialZone!);
    }
    WidgetsBinding.instance.addObserver(this);

    searchRenewalWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final data = cachedData;
      if (data != null) _maybePromptOverlayOnTripStart(data);
      if (data != null) _maybePromptSearchRenewal(data);
    });

    passengerForegroundPushSubscription =
        expressForegroundPushEvents().listen(_handleForegroundPushEvent);
    _subscribeZoneServiceCatalog();
    unawaited(_loadRideServices());

    final initial = widget.initialState;
    if (initial != null) {
      cachedData = _passengerDataFromRawState(initial);
      passengerOfferPresentationActive = cachedData!.offers.isNotEmpty;
      if (passengerOfferPresentationActive) {
        passengerOfferPresentationEpoch++;
      }
      homeFuture = Future.value(cachedData!);
      _syncPassengerOfferRealtime(cachedData!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshHome();
      });
    } else {
      homeFuture = _load(++loadRevision);
    }

    _locate();
    _startPassengerMapFollow();
    // Quick actions open the *same* native destination selector used by the
    // regular Taxi/Envíos form; no duplicate flow or request is created.
    if (widget.openDestinationPickerOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && cachedData?.activeTrip == null &&
            cachedData?.openRide == null) {
          unawaited(_pickDestination());
          widget.onDestinationPickerOpened?.call();
        }
      });
    }

    // Refresco general de respaldo únicamente cuando el usuario está inactivo.
    // Durante una búsqueda/viaje usamos sincronización localizada para no
    // reconstruir el Home mientras escribe, arrastra el mapa o usa un panel.
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final data = cachedData;
      if (data?.openRide == null &&
          data?.activeTrip == null &&
          data?.activeDelivery == null) {
        _refreshHome();
      }
    });

    // Refresco crítico durante una solicitud abierta. Es intencionalmente
    // independiente del refresco general: si Realtime o la push no llegan,
    // passenger_home_state vuelve a validar oferta/viaje y actualiza la UI.
    // Respaldo fuerte de presentación: mantiene la pantalla sincronizada
    // incluso cuando el evento Realtime o la push no despiertan la UI.
    passengerCriticalStateTimer =
        Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_refreshPassengerCriticalState());
    });
    unawaited(_refreshPassengerCriticalState());

    // Fuente independiente de ofertas: no depende del estado del Home.
    passengerLiveOfferTimer =
        Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshPassengerLiveOfferState());
    });
    unawaited(_refreshPassengerLiveOfferState());
  }

  @override
  void didUpdateWidget(covariant PassengerMapHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextZone = widget.initialZone;
    if (nextZone == null || nextZone.isEmpty) return;

    final nextId = nextZone['id']?.toString();
    final currentId = activeZone?['id']?.toString();
    if (nextId != null && nextId == currentId) return;
    // Never replace a GPS-resolved Iquique zone with an older Bolivia
    // landing update that happened to arrive after the map opened.
    if (zoneResolvedByCoordinates) return;

    activeZone = Map<String, dynamic>.from(nextZone);
  }

  void _subscribeZoneServiceCatalog() {
    zoneServiceCatalogChannel?.unsubscribe();
    zoneServiceCatalogChannel = supabase
        .channel('passenger-zone-services-${widget.service.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'zone_service_catalog',
          callback: (_) => _scheduleZoneServiceCatalogRefresh(),
        )
        .subscribe();
  }

  void _scheduleZoneServiceCatalogRefresh() {
    if (!mounted) return;
    zoneServiceCatalogDebounce?.cancel();
    zoneServiceCatalogDebounce =
        Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final point = pickup == null
          ? current
          : LatLng(pickup!.latitude, pickup!.longitude);
      if (point == null) {
        unawaited(_loadRideServices());
      } else {
        unawaited(
          _loadRideServices(
            latitude: point.latitude,
            longitude: point.longitude,
          ),
        );
      }
    });
  }

  Future<void> _loadRideServices({
    double? latitude,
    double? longitude,
  }) async {
    final hasCoordinates = latitude != null && longitude != null;
    // A delayed global catalog response must not undo zone-specific fares,
    // payments or service selection resolved from the pickup coordinates.
    if (!hasCoordinates && zoneResolvedByCoordinates) return;
    final requestEpoch = ++rideCatalogRequestEpoch;
    try {
      final config = await widget.service.runtimeConfig();
      final settings = config['settings'] is Map
          ? Map<String, dynamic>.from(config['settings'] as Map)
          : <String, dynamic>{};

      List<Map<String, dynamic>> rows;
      List<Map<String, dynamic>> ridePaymentMethods =
          <Map<String, dynamic>>[];
      Map<String, dynamic>? zone;
      var outsideCoverage = false;

      if (latitude != null && longitude != null) {
        final context = await widget.service.zoneContext(
          latitude: latitude,
          longitude: longitude,
          audience: 'passenger',
        );
        outsideCoverage = context['inside_coverage'] != true;
        final rawZone = context['zone'];
        zone = rawZone is Map
            ? Map<String, dynamic>.from(rawZone)
            : null;
        final rawServices = context['services'];
        rows = rawServices is List
            ? rawServices
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];
        final rawPaymentMethods = context['payment_methods'];
        ridePaymentMethods = rawPaymentMethods is List
            ? rawPaymentMethods
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];
      } else {
        rows = await widget.service.serviceCatalog(audience: 'passenger');
      }

      final canSendParcel = hasCoordinates &&
          rows.any((row) =>
            row['service_key']?.toString() == 'parcel' &&
            row['enabled'] == true && row['passenger_visible'] == true);
      final visibleServices = rows
          .where((row) =>
              row['passenger_visible'] != false &&
              row['service_key']?.toString() != 'delivery' &&
              row['service_key']?.toString() != 'parcel')
          .toList();
      if (!mounted || requestEpoch != rideCatalogRequestEpoch) return;

      // Antes de resolver el GPS conservamos el respaldo local. Una vez que
      // existe una coordenada real, nunca inventamos servicios fuera de zona.
      final usableServices = latitude == null || longitude == null
          ? (visibleServices.isEmpty ? _fallbackRideServices : visibleServices)
          : visibleServices;
      final currentAvailable = usableServices.any(
        (row) =>
            row['service_key']?.toString() == category &&
            row['enabled'] != false,
      );
      final firstAvailable = usableServices.where(
        (row) => row['enabled'] != false,
      );

      final effectiveSettings = Map<String, dynamic>.from(settings);
      if (zone != null && ridePaymentMethods.isNotEmpty) {
        // La lista del backend es autoritativa por zona y por entorno.
        // No inferimos Mercado Pago/VeriPagos por país: solo mostramos
        // métodos que administración marcó enabled + use_rides.
        effectiveSettings
          ..['allow_cash'] = false
          ..['allow_driver_qr'] = false
          ..['allow_card'] = false
          ..['allow_wallet'] = false
          ..['allow_pagorut'] = false
          ..['allow_mercadopago'] = false
          ..['allow_santander'] = false
          ..['allow_mach'] = false
          ..['allow_tenpo'] = false;

        for (final method in ridePaymentMethods) {
          switch (method['provider_key']?.toString()) {
            case 'cash':
              effectiveSettings['allow_cash'] = true;
              break;
            case 'driver_qr':
              effectiveSettings['allow_driver_qr'] = true;
              break;
            case 'card':
              effectiveSettings['allow_card'] = true;
              break;
            case 'wallet':
              effectiveSettings['allow_wallet'] = true;
              break;
            case 'pagorut':
            case 'veripagos_qr':
              effectiveSettings['allow_pagorut'] = true;
              break;
            case 'mercado_pago':
              effectiveSettings['allow_mercadopago'] = true;
              break;
            case 'santander':
              effectiveSettings['allow_santander'] = true;
              break;
            case 'mach':
              effectiveSettings['allow_mach'] = true;
              break;
            case 'tenpo':
              effectiveSettings['allow_tenpo'] = true;
              break;
          }
        }
      }

      final allowedPayments = <String>[
        if (effectiveSettings['allow_cash'] != false) 'cash',
        if (effectiveSettings['allow_driver_qr'] == true) 'driver_qr',
        if (effectiveSettings['allow_card'] == true) 'card',
        if (effectiveSettings['allow_wallet'] == true) 'wallet',
        if (effectiveSettings['allow_pagorut'] == true) 'pagorut',
        if (effectiveSettings['allow_mercadopago'] == true) 'mercado_pago',
        if (effectiveSettings['allow_santander'] == true) 'santander',
        if (effectiveSettings['allow_mach'] == true) 'mach',
        if (effectiveSettings['allow_tenpo'] == true) 'tenpo',
      ];

      String? preferredPayment;
      if (!paymentInitializedFromProfile && allowedPayments.isNotEmpty) {
        try {
          final user = await widget.service.myUser();
          preferredPayment =
              user?['preferred_payment_method']?.toString();
        } catch (_) {
          preferredPayment = null;
        }
      }

      var categoryChanged = false;
      setState(() {
        rideServices = usableServices;
        parcelAvailable = canSendParcel;
        if (hasCoordinates && !canSendParcel && serviceType == 'delivery') {
          serviceType = 'ride';
        }
        runtimeSettings = effectiveSettings;
        // A catalog refresh without coordinates must never erase the last
        // authoritative zone; otherwise Chile briefly falls back to BOB/Bs.
        if (zone != null) {
          activeZone = zone;
          zoneResolvedByCoordinates = true;
        }
        zoneOutsideCoverage = latitude != null && longitude != null
            ? outsideCoverage
            : zoneOutsideCoverage;
        if (!currentAvailable && usableServices.isNotEmpty) {
          final next = firstAvailable.isNotEmpty
              ? firstAvailable.first
              : usableServices.first;
          final nextCategory =
              next['service_key']?.toString() ?? 'motorcycle';
          categoryChanged = nextCategory != category;
          category = nextCategory;
          fareManuallyEdited = false;
        }
        if (!paymentInitializedFromProfile &&
            allowedPayments.isNotEmpty) {
          payment = preferredPayment != null &&
                  allowedPayments.contains(preferredPayment)
              ? preferredPayment!
              : (allowedPayments.contains(payment)
                  ? payment
                  : allowedPayments.first);
          paymentInitializedFromProfile = true;
        } else if (allowedPayments.isNotEmpty &&
            !allowedPayments.contains(payment)) {
          payment = allowedPayments.first;
        }
        if (settings['scheduled_rides_enabled'] == false) {
          scheduledFor = null;
        }
      });

      if (categoryChanged && routeConfirmed && destination != null) {
        unawaited(_refreshFareQuote());
      }
    } catch (_) {
      // Si falla una actualización de red mantenemos el último catálogo válido.
    }
  }

  Future<void> _refreshPassengerLiveOfferState() async {
    if (!mounted || passengerLiveOfferInFlight) return;

    // Realtime + push son la vía principal. El sondeo de respaldo solo tiene
    // sentido mientras existe una solicitud abierta; antes se consultaba aun
    // estando el pasajero inactivo y generaba miles de requests innecesarios.
    final currentData = cachedData;
    if (currentData == null) return;
    if (currentData.openRide == null ||
        currentData.activeTrip != null ||
        currentData.activeDelivery != null) {
      final hadLiveOfferState =
          passengerLiveOfferRide != null || passengerLiveOffers.isNotEmpty;
      passengerLiveOfferRide = null;
      passengerLiveOffers = <Map<String, dynamic>>[];
      passengerLiveOfferStateReady = true;
      if (hadLiveOfferState && mounted) {
        setState(() {
          passengerOfferPresentationActive = false;
          passengerOfferPresentationEpoch++;
          panelRevision++;
        });
      }
      return;
    }

    passengerLiveOfferInFlight = true;

    try {
      final raw = await widget.service
          .passengerLiveOfferState()
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;

      Map<String, dynamic>? mapOrNull(Object? value) {
        if (value is Map) return Map<String, dynamic>.from(value);
        return null;
      }

      final ride = mapOrNull(raw['ride']);
      final now = DateTime.now().toUtc();
      final offers = (raw['offers'] is List
              ? (raw['offers'] as List)
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList()
              : <Map<String, dynamic>>[])
          .where((offer) {
        if (offer['status']?.toString() != 'pending') return false;
        if (locallyExpiredPassengerOfferKeys.contains(
          _passengerOfferPresentationKey(offer),
        )) {
          return false;
        }
        final expiresAt =
            DateTime.tryParse(offer['expires_at']?.toString() ?? '')?.toUtc();
        return expiresAt == null || expiresAt.isAfter(now);
      }).toList();

      final oldRideId = passengerLiveOfferRide?['id']?.toString();
      final newRideId = ride?['id']?.toString();
      final changed = !passengerLiveOfferStateReady ||
          oldRideId != newRideId ||
          !_samePassengerOfferList(passengerLiveOffers, offers);

      passengerLiveOfferStateReady = true;
      if (!changed) return;

      final hadOffers = passengerLiveOffers.isNotEmpty;
      passengerLiveOfferRide =
          ride == null ? null : Map<String, dynamic>.from(ride);
      passengerLiveOffers = offers
          .map((offer) => Map<String, dynamic>.from(offer))
          .toList();

      for (final offer in passengerLiveOffers) {
        locallyExpiredPassengerOfferKeys.remove(
          _passengerOfferPresentationKey(offer),
        );
      }

      ExpressDiagnosticsHub.note(
        passengerLiveOffers.isEmpty
            ? 'LIVE_OFFER_STATE_EMPTY'
            : 'LIVE_OFFER_STATE_RECEIVED',
      );

      if (passengerLiveOffers.isNotEmpty) {
        unawaited(
          AppErrorReporter.event(
            'PASSENGER_LIVE_OFFERS_RECEIVED',
            source: 'passenger_live_offer_state',
            screen: 'passenger_home',
            context: {
              'offer_count': passengerLiveOffers.length,
              'ride_status': passengerLiveOfferRide?['status']?.toString(),
              'ride_id': passengerLiveOfferRide?['id']?.toString(),
            },
          ),
        );
      }

      if (mounted) {
        setState(() {
          if (hadOffers != passengerLiveOffers.isNotEmpty) {
            panelRevision++;
            passengerOfferPresentationEpoch++;
          }
        });
      }
    } catch (error, stack) {
      unawaited(
        AppErrorReporter.capture(
          error,
          stack,
          source: 'passenger_live_offer_state',
          screen: 'passenger_home',
          eventName: 'PASSENGER_LIVE_OFFER_REFRESH_FAILED',
          context: {
            'cached_open_ride': cachedData?.openRide?['id']?.toString(),
            'cached_offer_count': cachedData?.offers.length ?? 0,
          },
        ),
      );
      // Un error temporal no borra la última oferta válida ya visible.
    } finally {
      passengerLiveOfferInFlight = false;
    }
  }

  void _observePassengerTripTransition(_PassengerStateData? data) {
    final trip = data?.activeTrip;
    final tripId = trip?['id']?.toString();
    final status = trip?['status']?.toString();
    if (tripId == null || status == null) return;

    if (lastAnimatedPassengerTripId == tripId &&
        lastAnimatedPassengerTripStatus == status) {
      return;
    }

    final previousStatus = lastAnimatedPassengerTripStatus;
    lastAnimatedPassengerTripId = tripId;
    lastAnimatedPassengerTripStatus = status;

    // La primera carga ya representa el estado actual. Animamos especialmente
    // los cambios remotos que llegan después de estar montada la pantalla.
    if (previousStatus == null && status != 'driver_assigned') return;

    String? title;
    String? subtitle;
    IconData icon = Icons.local_taxi_rounded;
    String event = 'PASSENGER_TRIP_STATE_' + status.toUpperCase();

    switch (status) {
      case 'driver_assigned':
        title = 'Conductor confirmado';
        subtitle = 'Tu viaje ya tiene conductor asignado.';
        icon = Icons.verified_rounded;
        break;
      case 'driver_arriving':
        title = 'Tu conductor va en camino';
        subtitle = 'Puedes seguir su llegada directamente en el mapa.';
        icon = Icons.directions_car_filled_rounded;
        break;
      case 'driver_waiting':
        title = 'Tu conductor llegó';
        subtitle = 'Ya se encuentra en el punto de recogida.';
        icon = Icons.location_on_rounded;
        break;
      case 'in_progress':
        title = 'Viaje iniciado';
        subtitle = 'Tu viaje está en curso. Buen viaje.';
        icon = Icons.route_rounded;
        break;
      case 'emergency':
        title = 'Alerta de emergencia activa';
        subtitle = 'Express registró el estado de emergencia del viaje.';
        icon = Icons.sos_rounded;
        break;
    }

    if (trip != null && _expressIsParcelTrip(trip)) {
      icon = Icons.inventory_2_outlined;
      switch (status) {
        case 'driver_assigned':
          title = 'Repartidor confirmado';
          subtitle = 'Tu paquete tiene un conductor asignado.';
          break;
        case 'driver_arriving':
          title = 'Repartidor en camino a recoger';
          subtitle = 'Sigue su llegada para entregar el paquete.';
          break;
        case 'driver_waiting':
          title = 'El repartidor llegó a recoger';
          subtitle = 'Entrega tu paquete al repartidor asignado.';
          break;
        case 'in_progress':
          title = 'Paquete recogido';
          subtitle = 'El paquete va en camino al destinatario.';
          break;
        case 'emergency':
          title = 'Alerta en tu envío';
          subtitle = 'Se registró una alerta relacionada con el paquete.';
          break;
      }
    }
    if (title == null || subtitle == null) return;
    unawaited(HapticFeedback.selectionClick());
    unawaited(
      AppErrorReporter.event(
        event,
        source: 'ride_state_change',
        screen: 'passenger_home',
        context: {'status': status},
      ),
    );
  }

  _PassengerStateData _passengerDataFromRawState(
    Map<String, dynamic> state,
  ) {
    Map<String, dynamic>? mapOrNull(Object? value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    List<Map<String, dynamic>> listOfMaps(Object? value) {
      if (value is! List) return <Map<String, dynamic>>[];
      return value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }

    final now = DateTime.now().toUtc();
    final activeOffers = listOfMaps(state['offers']).where((offer) {
      if (offer['status']?.toString() != 'pending') return false;
      if (locallyExpiredPassengerOfferKeys.contains(
        _passengerOfferPresentationKey(offer),
      )) {
        return false;
      }
      final expiresAt =
          DateTime.tryParse(offer['expires_at']?.toString() ?? '')?.toUtc();
      return expiresAt == null || expiresAt.isAfter(now);
    }).toList();

    return _PassengerStateData(
      service: widget.service,
      openRide: mapOrNull(state['open_ride']),
      activeTrip: mapOrNull(state['active_trip']),
      activeDelivery: mapOrNull(state['active_delivery']),
      offers: activeOffers,
      saved: listOfMaps(state['saved']),
      counterpart: mapOrNull(state['counterpart']),
      driverProfile: mapOrNull(state['driver_profile']),
    );
  }

  String _passengerOfferPresentationKey(Map<String, dynamic> offer) {
    return (offer['id']?.toString() ?? '') + ':' + (offer['created_at']?.toString() ?? '') + ':' + (offer['proposed_fare']?.toString() ?? '');
  }

  bool _samePassengerOfferList(
    List<Map<String, dynamic>> first,
    List<Map<String, dynamic>> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (_passengerOfferPresentationKey(first[index]) !=
              _passengerOfferPresentationKey(second[index]) ||
          first[index]['status']?.toString() !=
              second[index]['status']?.toString() ||
          authorizedOfferPortraitPath(first[index]) !=
              authorizedOfferPortraitPath(second[index])) {
        return false;
      }
    }
    return true;
  }

  void _settlePassengerSearchSheetImmediately() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !sheetController.isAttached) return;
      try { sheetController.jumpTo(.36); } catch (_) {}
    });
  }

  Future<void> _refreshPassengerCriticalState() async {
    if (!mounted || passengerCriticalStateInFlight) return;

    final before = cachedData;
    if (before == null) return;

    final beforeActiveTripId = before.activeTrip?['id']?.toString();
    final beforeActiveTripStatus = before.activeTrip?['status']?.toString();
    String? beforeRideId;
    if (beforeActiveTripId == null) {
      beforeRideId = before.openRide == null
          ? null
          : before.openRide!['id']?.toString();
    }
    if ((beforeRideId == null || beforeRideId.isEmpty) &&
        (beforeActiveTripId == null || beforeActiveTripId.isEmpty)) {
      return;
    }

    Map<String, dynamic>? mapOrNull(Object? value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    passengerCriticalStateInFlight = true;
    try {
      if (beforeActiveTripId != null && beforeActiveTripId.isNotEmpty) {
        final liveTrip = await widget.service
            .passengerActiveTripLiveState()
            .timeout(const Duration(seconds: 3));

        if (!mounted) return;
        if (liveTrip == null) {
          // El servidor ya no lo cuenta como activo: no puede reaparecer.
          passengerFinishedTrips.markFinished(beforeActiveTripId);
          _refreshHome();
          return;
        }

        final nextTripId = liveTrip['id']?.toString();
        if (nextTripId != beforeActiveTripId) return;

        final nextTripStatus = liveTrip['status']?.toString();
        final nextDriverProfile =
            mapOrNull(liveTrip['driver_profile']) ?? before.driverProfile;

        final beforeLat = asDouble(before.driverProfile?['latitude']);
        final beforeLng = asDouble(before.driverProfile?['longitude']);
        final nextLat = asDouble(nextDriverProfile?['latitude']);
        final nextLng = asDouble(nextDriverProfile?['longitude']);
        final waitingChanged =
            before.activeTrip?['driver_waiting_since']?.toString() !=
                liveTrip['driver_waiting_since']?.toString() ||
            before.activeTrip?['passenger_on_way_at']?.toString() !=
                liveTrip['passenger_on_way_at']?.toString();

        final changed = beforeActiveTripStatus != nextTripStatus ||
            beforeLat != nextLat ||
            beforeLng != nextLng ||
            waitingChanged;
        if (!changed) return;

        final next = _PassengerStateData(
          service: widget.service,
          openRide: null,
          activeTrip: passengerFinishedTrips.visibleActiveTrip(liveTrip),
          activeDelivery: before.activeDelivery,
          offers: const [],
          saved: before.saved,
          counterpart: before.counterpart,
          driverProfile: nextDriverProfile,
          driverVehicle: before.driverVehicle,
          pendingRating: before.pendingRating,
          viewedCount: 0,
          viewers: const [],
          nearbyDrivers: const [],
        );

        cachedData = next;
        if (mounted) {
          setState(() {
            if (beforeActiveTripStatus != nextTripStatus) panelRevision++;
            homeFuture = Future.value(next);
          });
        }
        return;
      }

      final state = await widget.service
          .passengerHomeState()
          .timeout(const Duration(seconds: 3));

      if (!mounted) return;

      List<Map<String, dynamic>> listOfMaps(Object? value) {
        if (value is! List) return <Map<String, dynamic>>[];
        return value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }

      final openRide = mapOrNull(state['open_ride']);
      final activeTrip = mapOrNull(state['active_trip']);
      final activeDelivery = mapOrNull(state['active_delivery']);
      final now = DateTime.now().toUtc();

      final activeOffers = listOfMaps(state['offers']).where((offer) {
        if (offer['status']?.toString() != 'pending') return false;
        if (locallyExpiredPassengerOfferKeys.contains(
          _passengerOfferPresentationKey(offer),
        )) {
          return false;
        }
        final expiresAt =
            DateTime.tryParse(offer['expires_at']?.toString() ?? '')?.toUtc();
        return expiresAt == null || expiresAt.isAfter(now);
      }).toList();

      if (activeTrip != null) {
        stopExpressAlertSound();
        passengerOfferOverlayOffers = <Map<String, dynamic>>[];
        passengerOfferOverlayRideId = null;

        final next = _PassengerStateData(
          service: widget.service,
          openRide: null,
          activeTrip: activeTrip,
          activeDelivery: activeDelivery,
          offers: const [],
          saved: before.saved,
          counterpart: mapOrNull(state['counterpart']) ?? before.counterpart,
          driverProfile:
              mapOrNull(state['driver_profile']) ?? before.driverProfile,
          driverVehicle: before.driverVehicle,
          pendingRating: before.pendingRating,
          viewedCount: 0,
          viewers: const [],
          nearbyDrivers: const [],
        );

        cachedData = next;
        if (mounted) {
          setState(() {
            panelRevision++;
            homeFuture = Future.value(next);
          });
        }
        return;
      }

      final openRideId = openRide?['id']?.toString();
      if (openRideId == null || openRideId.isEmpty) {
        passengerOfferOverlayOffers = <Map<String, dynamic>>[];
        passengerOfferOverlayRideId = null;
        if (mounted) _refreshHome();
        return;
      }

      if (openRideId != beforeRideId) return;

      if (activeOffers.isNotEmpty) {
        passengerOfferOverlayRideId = openRideId;
        passengerOfferOverlayRide = openRide == null
            ? (before.openRide == null
                ? null
                : Map<String, dynamic>.from(before.openRide!))
            : Map<String, dynamic>.from(openRide);
        passengerOfferOverlayOffers = activeOffers
            .map((offer) => Map<String, dynamic>.from(offer))
            .toList();
      }

      final next = _PassengerStateData(
        service: widget.service,
        openRide: openRide,
        activeTrip: null,
        activeDelivery: activeDelivery,
        offers: activeOffers.isNotEmpty ? activeOffers : before.offers,
        saved: before.saved,
        counterpart: mapOrNull(state['counterpart']) ?? before.counterpart,
        driverProfile:
            mapOrNull(state['driver_profile']) ?? before.driverProfile,
        driverVehicle: before.driverVehicle,
        pendingRating: before.pendingRating,
        viewedCount: before.viewedCount,
        viewers: before.viewers,
        nearbyDrivers: before.nearbyDrivers,
      );

      cachedData = next;
      _syncPassengerOfferRealtime(next);

      if (activeOffers.isNotEmpty && mounted) {
        setState(() {
          panelRevision++;
          homeFuture = Future.value(next);
        });
        _ensurePassengerOfferVisible();
      }
    } catch (_) {
      // Realtime, push y el refresco general siguen como respaldo.
    } finally {
      passengerCriticalStateInFlight = false;
    }
  }

  void _ensurePassengerOfferVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final current = cachedData;
      String? rideId;
      if (current != null && current.activeTrip == null) {
        rideId = current.openRide?['id']?.toString();
      }
      if (rideId == null ||
          rideId.isEmpty ||
          current == null ||
          !current.offers.isNotEmpty) {
        return;
      }

      // Si el estado ya contiene ofertas pero la capa visual continúa en cero,
      // recreamos únicamente el home de pasajero. Esto equivale al efecto que
      // hoy obtiene el usuario al cerrar/abrir, pero ocurre automáticamente.
      if (ExpressDiagnosticsHub.passengerUi.value.uiOfferCount == 0) {
        ExpressDiagnosticsHub.note('OFFER_UI_HARD_REFRESH');
        widget.onHardReset();
      }
    });
  }

  Future<void> _handleForegroundPushEvent(String type) async {
    if (!mounted) return;

    final isRideOfferPush = type == 'ride_offer' ||
        type == 'new_offer' ||
        type == 'ride_offer_received';
    if (isRideOfferPush) {
      // La alerta audible pertenece a la oferta realmente incorporada en
      // _OffersCard. La push solo acelera la sincronización; hacer sonar aquí
      // también duplicaba el aviso para una misma oferta.
      ExpressDiagnosticsHub.note('FOREGROUND_PUSH_RIDE_OFFER');
      unawaited(_refreshPassengerLiveOfferState());
    }

    if (type == 'ride_assigned' ||
        type == 'trip_status' ||
        type == 'trip_cancelled') {
      // La push acelera el cambio de etapa en vez de esperar al siguiente
      // polling crítico (~1.4 s). Sigue existiendo polling como respaldo.
      unawaited(_refreshPassengerCriticalState());
    }

    final currentData = cachedData;
    final rideId = currentData?.activeTrip == null
        ? (currentData?.openRide?['id']?.toString())
        : null;

    // La push es un acelerador, nunca la única fuente. Si llega mientras la
    // aplicación está abierta hacemos la lectura directa de ofertas de forma
    // inmediata; el polling + Realtime siguen cubriendo el caso sin push.
    if (rideId != null && rideId.isNotEmpty) {
      try {
        final rows = await widget.service.offersForRide(rideId);
        if (mounted &&
            cachedData?.activeTrip == null &&
            cachedData?.openRide?['id']?.toString() == rideId) {
          _applyRealtimePassengerOffers(
            rideId,
            rows,
            authoritative: true,
          );

          // Android muestra la notificación visible. Dentro de Express solo
          // sincronizamos la tarjeta para evitar el mismo aviso dos veces.
        }
      } catch (_) {}
    }

    // Para ofertas, la consulta directa anterior ya actualiza la pantalla.
    // El refresco general queda para otros tipos de cambio y nunca compite con
    // el primer frame de la lista de ofertas.
    if (type != 'ride_offer' &&
        type != 'ride_offer_sent' &&
        type != 'new_offer' &&
        mounted) {
      _refreshHome();
    }
  }

  void _startPassengerOfferBootstrapPoll(String rideId) {
    passengerOfferBootstrapTimer?.cancel();
    passengerOfferBootstrapTimer = null;

    Future<void> checkNow() async {
      if (!mounted ||
          passengerOfferRealtimeRideId != rideId ||
          passengerOfferBootstrapInFlight) {
        return;
      }

      final currentData = cachedData;
      if (currentData == null ||
          currentData.activeTrip != null ||
          currentData.openRide?['id']?.toString() != rideId) {
        passengerOfferBootstrapTimer?.cancel();
        passengerOfferBootstrapTimer = null;
        return;
      }

      passengerOfferBootstrapInFlight = true;
      try {
        final offerStateRevisionAtRequest = passengerOfferStateRevision;

        // Fuente ligera y directa: no depende del RPC grande del home, de la
        // push ni de que Realtime alcance a entregar el primer INSERT.
        final rows = await widget.service.offersForRide(rideId);

        if (!mounted || passengerOfferRealtimeRideId != rideId) return;

        // Una consulta iniciada antes de que una oferta más nueva se aplicara
        // no puede volver luego con [] y borrar ese estado nuevo.
        if (rows.isEmpty &&
            offerStateRevisionAtRequest != passengerOfferStateRevision) {
          return;
        }

        ExpressDiagnosticsHub.note(
          rows.isEmpty ? 'POLL_EMPTY' : 'OFFER_POLL_RECEIVED',
        );
        _applyRealtimePassengerOffers(
          rideId,
          rows,
          authoritative: true,
        );

        // offersForRide ya devuelv…124157 tokens truncated…  ? Map<String, dynamic>.from(rawUser)
        : <String, dynamic>{};

    final name = driverUser['full_name']?.toString().trim();
    final completedTrips =
        (driver['completed_trips'] as num?)?.toInt() ?? 0;
    final eta = widget.offer['eta_minutes']?.toString() ?? '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _riderSoftSurface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _riderBorder(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _rideMoney(
                        widget.offer['proposed_fare'],
                        widget.offer['currency'],
                      ),
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(
                        '$eta min',
                        style: TextStyle(
                          color: _riderMuted(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: remaining <= 5
                      ? const Color(0xFFFFE4E6)
                      : expressBlue.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${remaining}s',
                  style: TextStyle(
                    color: remaining <= 5
                        ? const Color(0xFFBE123C)
                        : expressBlue,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              _OfferDriverPortrait(
                driverId: widget.offer['driver_id']?.toString(),
                approvedPath: authorizedOfferPortraitPath(widget.offer),
                fallbackUrl: driverUser['avatar_url']?.toString(),
                radius: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name?.isNotEmpty == true ? name! : 'Conductor Express',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '★ ' +
                          (driver['rating']?.toString() ?? '5.0') +
                          (completedTrips > 0
                              ? ' · $completedTrips viajes'
                              : ''),
                      style: TextStyle(
                        color: _riderMuted(context),
                        fontSize: 10.5,
                      ),
                    ),
                    Text(
                      driver['vehicle_summary']?.toString().trim().isNotEmpty ==
                              true
                          ? driver['vehicle_summary'].toString()
                          : 'Vehículo por confirmar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _riderMuted(context),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: widget.onDecline,
                    child: const Text('Rechazar'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton(
                    onPressed: widget.onChoose,
                    style: FilledButton.styleFrom(
                      backgroundColor: expressBlue,
                    ),
                    child: const Text('Aceptar'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverActiveTripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final Map<String, dynamic>? passenger;
  final VoidCallback onMap;
  final VoidCallback onChat;
  final VoidCallback onCall;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;

  const _DriverActiveTripCard({
    required this.trip,
    required this.passenger,
    required this.onMap,
    required this.onChat,
    required this.onCall,
    this.primaryLabel,
    this.onPrimary,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final ride = trip['ride_requests'] is Map
        ? Map<String, dynamic>.from(trip['ride_requests'] as Map)
        : <String, dynamic>{};
    final passengerName = passenger?['full_name']?.toString().trim();
    final status = trip['status']?.toString() ?? 'driver_assigned';
    final isParcel = _expressIsParcelTrip(trip);
    final sender = ride['parcel_sender_name']?.toString().trim() ?? '';
    final recipient = ride['parcel_recipient_name']?.toString().trim() ?? '';
    final recipientPhone = ride['parcel_recipient_phone']?.toString().trim() ?? '';
    final pickup = _expressDriverRouteLabel(
      ride,
      addressKey: 'pickup_address',
      latitudeKey: 'pickup_latitude',
      longitudeKey: 'pickup_longitude',
      fallback: 'Origen',
    );
    final destination = _expressDriverRouteLabel(
      ride,
      addressKey: 'destination_address',
      latitudeKey: 'destination_latitude',
      longitudeKey: 'destination_longitude',
      fallback: 'Destino',
    );
    final fare = asDouble(trip['final_fare']) ??
        asDouble(ride['proposed_fare']);
    final currency =
        ride['currency']?.toString() ?? trip['currency']?.toString() ?? 'BOB';
    final dark = _riderHomeDark(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF141414) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _riderBorder(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: expressBlue.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isParcel ? Icons.inventory_2_outlined
                      : Icons.local_taxi_rounded,
                  color: expressBlue,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isParcel ? _parcelTripStatus(status) : _tripStatus(status),
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isParcel
                          ? (status == 'in_progress'
                              ? 'Destinatario: ${recipient.isEmpty ? 'Por confirmar' : recipient}'
                              : 'Remitente: ${sender.isEmpty ? 'Cliente' : sender}')
                          : (passengerName == null || passengerName.isEmpty
                              ? 'Pasajero del viaje' : passengerName),
                      style: TextStyle(
                        color: _riderMuted(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (fare != null)
                Text(
                  _rideMoney(fare, currency),
                  style: const TextStyle(
                    color: expressBlue,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _riderSoftSurface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _riderBorder(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DriverRouteLine(
                  icon: Icons.trip_origin_rounded,
                  text: pickup,
                ),
                const SizedBox(height: 8),
                _DriverRouteLine(
                  icon: Icons.location_on_rounded,
                  text: destination,
                ),
              ],
            ),
          ),
          if (isParcel) ...[
            if (status == 'in_progress' && recipientPhone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text('Teléfono del destinatario: $recipientPhone',
                  style: TextStyle(color: _riderMuted(context), fontSize: 12)),
              ),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _TripActionButton(
                  icon: Icons.navigation_rounded,
                  label: 'Waze',
                  onTap: onMap,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _TripActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chat',
                  onTap: onChat,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _TripActionButton(
                  icon: Icons.phone_outlined,
                  label: 'Llamar',
                  onTap: onCall,
                ),
              ),
            ],
          ),
          if (primaryLabel != null || onCancel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (primaryLabel != null)
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: onPrimary,
                        style: FilledButton.styleFrom(
                          backgroundColor: expressBlue,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(primaryLabel!),
                      ),
                    ),
                  ),
                if (primaryLabel != null && onCancel != null)
                  const SizedBox(width: 8),
                if (onCancel != null)
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD92D20),
                          side: const BorderSide(
                            color: Color(0xFFF3B4AE),
                          ),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (status == 'driver_waiting') ...[
            const SizedBox(height: 10),
            if (!isParcel)
              _DriverPickupWaitNotice(
                waitingSince:
                    trip['driver_waiting_since']?.toString(),
                passengerOnWayAt:
                    trip['passenger_on_way_at']?.toString(),
              ),
            const SizedBox(height: 8),
            Text(
              isParcel
                ? 'Cuando recibas el paquete del remitente, confirma la recogida.'
                : 'Pide al pasajero el PIN de 4 dígitos antes de iniciar el viaje.',
              style: TextStyle(
                color: _riderMuted(context),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DriverPickupWaitNotice extends StatefulWidget {
  final String? waitingSince;
  final String? passengerOnWayAt;

  const _DriverPickupWaitNotice({
    required this.waitingSince,
    required this.passengerOnWayAt,
  });

  @override
  State<_DriverPickupWaitNotice> createState() =>
      _DriverPickupWaitNoticeState();
}

class _DriverPickupWaitNoticeState
    extends State<_DriverPickupWaitNotice> {
  Timer? timer;
  // Última marca real del servidor: si una actualización llega sin ella, el
  // reloj no vuelve a empezar desde el montaje del widget.
  DateTime? lastKnownStart;

  @override
  void initState() {
    super.initState();
    lastKnownStart = parsePickupWaitStart(widget.waitingSince);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _DriverPickupWaitNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    lastKnownStart =
        parsePickupWaitStart(widget.waitingSince) ?? lastKnownStart;
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  /// Segundos restantes; null mientras el servidor no entregue la marca.
  int? get remainingSeconds => pickupWaitRemainingSeconds(
        start: effectivePickupWaitStart(
          serverStart: parsePickupWaitStart(widget.waitingSince),
          lastKnownStart: lastKnownStart,
        ),
        now: DateTime.now(),
      );

  String? get clock {
    final seconds = remainingSeconds;
    return seconds == null ? null : pickupWaitClock(seconds);
  }

  @override
  Widget build(BuildContext context) {
    final passengerOnWay =
        widget.passengerOnWayAt != null && widget.passengerOnWayAt!.isNotEmpty;
    final expired = remainingSeconds == 0;
    final dark = _riderHomeDark(context);

    final background = dark
        ? passengerOnWay
            ? const Color(0xFF0B2B21)
            : expired
                ? const Color(0xFF351817)
                : const Color(0xFF332713)
        : passengerOnWay
            ? const Color(0xFFEAFBF3)
            : expired
                ? const Color(0xFFFFF1F0)
                : const Color(0xFFFFF8E8);
    final border = dark
        ? passengerOnWay
            ? const Color(0xFF176B52)
            : expired
                ? const Color(0xFF8C3A35)
                : const Color(0xFF805F22)
        : passengerOnWay
            ? const Color(0xFFABEFC6)
            : expired
                ? const Color(0xFFFDA29B)
                : const Color(0xFFFEDC89);
    final accent = dark
        ? passengerOnWay
            ? const Color(0xFF6CE9A6)
            : expired
                ? const Color(0xFFFF8A82)
                : const Color(0xFFFEC84B)
        : passengerOnWay
            ? const Color(0xFF067647)
            : expired
                ? const Color(0xFFB42318)
                : const Color(0xFFB54708);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            passengerOnWay
                ? Icons.directions_walk_rounded
                : Icons.timer_outlined,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              passengerOnWay
                  ? 'El pasajero avisó “Ya voy”. Tiempo de abordaje: ${clock ?? 'calculando…'}'
                  : expired
                      ? 'Se cumplió el tiempo de cortesía de 5 minutos.'
                      : clock == null
                          ? 'Calculando el tiempo de abordaje…'
                          : 'Al pasajero le quedan $clock para abordar.',
              style: TextStyle(
                color: _riderText(context),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverRouteLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DriverRouteLine({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: expressBlue, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _riderText(context),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _PassengerActiveTripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final Map<String, dynamic>? driver;
  final Map<String, dynamic>? driverProfile;
  final Map<String, dynamic>? vehicle;
  final Map<String, dynamic> adSettings;
  final VoidCallback onMap;
  final VoidCallback onChat;
  final VoidCallback onCall;
  final VoidCallback onShare;
  final VoidCallback onEmergency;
  final Future<bool> Function() onPassengerOnWay;
  final VoidCallback? onCancel;

  const _PassengerActiveTripCard({
    required this.trip,
    required this.driver,
    required this.driverProfile,
    required this.vehicle,
    required this.adSettings,
    required this.onMap,
    required this.onChat,
    required this.onCall,
    required this.onShare,
    required this.onEmergency,
    required this.onPassengerOnWay,
    this.onCancel,
  });

  int? _etaMinutes() {
    final status = trip['status']?.toString();
    if (status == 'driver_waiting') return 0;
    if (status == 'in_progress' || status == 'completed') return null;

    final ride = trip['ride_requests'] is Map
        ? Map<String, dynamic>.from(trip['ride_requests'] as Map)
        : <String, dynamic>{};
    final driverLat = asDouble(driverProfile?['latitude']);
    final driverLng = asDouble(driverProfile?['longitude']);
    final pickupLat = asDouble(ride['pickup_latitude']);
    final pickupLng = asDouble(ride['pickup_longitude']);
    if (driverLat == null ||
        driverLng == null ||
        pickupLat == null ||
        pickupLng == null) {
      return null;
    }

    final km = const Distance().as(
          LengthUnit.Kilometer,
          LatLng(driverLat, driverLng),
          LatLng(pickupLat, pickupLng),
        );
    return (km * 3).ceil().clamp(1, 30).toInt();
  }

  String _vehicleLabel() {
    final parts = <String>[
      if (vehicle?['color']?.toString().trim().isNotEmpty == true)
        vehicle!['color'].toString().trim(),
      if (vehicle?['brand']?.toString().trim().isNotEmpty == true)
        vehicle!['brand'].toString().trim(),
      if (vehicle?['model']?.toString().trim().isNotEmpty == true)
        vehicle!['model'].toString().trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    final summary = driverProfile?['vehicle_summary']?.toString().trim();
    return summary == null || summary.isEmpty
        ? 'Vehículo por confirmar'
        : summary;
  }

  @override
  Widget build(BuildContext context) {
    final status = trip['status']?.toString() ?? 'driver_assigned';
    final isParcel = _expressIsParcelTrip(trip);
    final name = driver?['full_name']?.toString().trim();
    final avatar = driver?['avatar_url']?.toString().trim();
    final rating = driverProfile?['rating']?.toString() ?? '5.0';
    final completedTrips =
        (driverProfile?['completed_trips'] as num?)?.toInt() ?? 0;
    final plate = vehicle?['plate']?.toString().trim();
    final pin = trip['boarding_pin']?.toString().trim();
    final eta = _etaMinutes();
    final dark = _riderHomeDark(context);
    final beforeBoarding =
        ['driver_assigned', 'driver_arriving', 'driver_waiting']
            .contains(status);

    String headline;
    String supporting;
    switch (status) {
      case 'driver_arriving':
        headline = 'Conductor en camino';
        supporting = eta == null
            ? 'Sigue su ubicación en tiempo real'
            : 'Llega en aproximadamente $eta min';
        break;
      case 'driver_waiting':
        headline = 'Tu conductor llegó';
        supporting = 'Dirígete al punto de encuentro';
        break;
      case 'in_progress':
        headline = 'Viaje en curso';
        supporting = 'Vas camino a tu destino';
        break;
      case 'emergency':
        headline = 'Alerta de emergencia';
        supporting = 'El viaje está marcado como emergencia';
        break;
      default:
        headline = 'Conductor asignado';
        supporting = eta == null
            ? 'Preparando el viaje'
            : 'Aproximadamente $eta min para llegar';
    }

    if (isParcel) {
      switch (status) {
        case 'driver_arriving':
          headline = 'Repartidor camino a recoger';
          supporting = eta == null ? 'Preparando la recogida del paquete'
              : 'Llegará a recoger en aproximadamente $eta min';
          break;
        case 'driver_waiting':
          headline = 'Repartidor en la recogida';
          supporting = 'Entrega el paquete al conductor asignado';
          break;
        case 'in_progress':
          headline = 'Paquete en camino';
          supporting = 'Tu envío se dirige al destinatario';
          break;
        default:
          headline = 'Repartidor asignado';
          supporting = 'Preparando la recogida de tu paquete';
      }
    }

    final surface = dark ? const Color(0xFF141414) : Colors.white;
    final soft = dark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F9FC);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _riderBorder(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: expressBlue.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  isParcel ? Icons.inventory_2_outlined
                      : Icons.local_taxi_rounded,
                  color: expressBlue,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      supporting,
                      style: TextStyle(
                        color: _riderMuted(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (eta != null && status != 'driver_waiting')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: expressBlue.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$eta min',
                    style: const TextStyle(
                      color: expressBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _riderBorder(context)),
            ),
            child: Row(
              children: [
                _PrivateDriverPortrait(
                  driverId: trip['driver_id']?.toString(),
                  path: driverProfile?['profile_photo_path']?.toString(),
                  fallbackUrl: avatar,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name == null || name.isEmpty ? 'Conductor' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _riderText(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '★ $rating' +
                            (completedTrips > 0
                                ? ' · $completedTrips viajes'
                                : ''),
                        style: TextStyle(
                          color: _riderMuted(context),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _vehicleLabel() +
                            (plate == null || plate.isEmpty
                                ? ''
                                : ' · $plate'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _riderMuted(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isParcel && beforeBoarding && pin != null && pin.isNotEmpty) ...[
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: expressBlue.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: expressBlue.withValues(alpha: .20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.pin_outlined,
                    color: expressBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'PIN para abordar',
                      style: TextStyle(
                        color: _riderText(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    pin,
                    style: const TextStyle(
                      color: expressBlue,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isParcel && status == 'driver_waiting') ...[
            const SizedBox(height: 11),
            _PassengerPickupWaitNotice(
              waitingSince: DateTime.tryParse(
                trip['driver_waiting_since']?.toString() ?? '',
              ),
              alreadyAcknowledged:
                  trip['passenger_on_way_at']?.toString().isNotEmpty == true,
              onAcknowledge: onPassengerOnWay,
            ),
          ],
          if (isParcel && status == 'driver_waiting')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Cuando el repartidor reciba el paquete, '
                'comenzará la ruta de entrega.',
                style: TextStyle(color: _riderMuted(context))),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TripActionButton(
                  icon: Icons.map_outlined,
                  label: 'Mapa',
                  onTap: onMap,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _TripActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chat',
                  onTap: onChat,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _TripActionButton(
                  icon: Icons.phone_outlined,
                  label: 'Llamar',
                  onTap: onCall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TripActionButton(
                  icon: Icons.share_outlined,
                  label: 'Compartir',
                  onTap: onShare,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _TripActionButton(
                  icon: Icons.sos_rounded,
                  label: 'Emergencia',
                  danger: true,
                  onTap: onEmergency,
                ),
              ),
            ],
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD92D20),
                  side: const BorderSide(
                    color: Color(0xFFD92D20),
                    width: 1.2,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Cancelar viaje',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PassengerPickupWaitNotice extends StatefulWidget {
  final DateTime? waitingSince;
  final bool alreadyAcknowledged;
  final Future<bool> Function() onAcknowledge;

  const _PassengerPickupWaitNotice({
    required this.waitingSince,
    required this.alreadyAcknowledged,
    required this.onAcknowledge,
  });

  @override
  State<_PassengerPickupWaitNotice> createState() =>
      _PassengerPickupWaitNoticeState();
}

class _PassengerPickupWaitNoticeState
    extends State<_PassengerPickupWaitNotice> {
  Timer? timer;
  late bool acknowledged;
  bool busy = false;
  DateTime now = DateTime.now();
  // Última marca real: una actualización sin ella no reinicia la cuenta.
  DateTime? lastKnownStart;

  @override
  void initState() {
    super.initState();
    acknowledged = widget.alreadyAcknowledged;
    lastKnownStart = widget.waitingSince;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant _PassengerPickupWaitNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alreadyAcknowledged) acknowledged = true;
    lastKnownStart = widget.waitingSince ?? lastKnownStart;
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  /// m:ss restante, o null mientras no haya marca del servidor (sin 5:00 falso).
  String? _remainingText() {
    final seconds = pickupWaitRemainingSeconds(
      start: effectivePickupWaitStart(
        serverStart: widget.waitingSince,
        lastKnownStart: lastKnownStart,
      ),
      now: now,
    );
    return seconds == null ? null : pickupWaitClock(seconds);
  }

  Future<void> _acknowledge() async {
    if (busy || acknowledged) return;
    setState(() => busy = true);
    try {
      await widget.onAcknowledge();
      if (!mounted) return;
      setState(() => acknowledged = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avisamos al conductor que ya vas.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo avisar: $error')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = _remainingText();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: expressBlue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: expressBlue.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: expressBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time == null
                      ? 'Calculando tiempo para abordar…'
                      : time == '0:00'
                          ? 'Tiempo de espera cumplido'
                          : 'Tienes $time para abordar',
                  style: TextStyle(
                    color: _riderText(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  acknowledged
                      ? 'El conductor ya sabe que vas.'
                      : 'Confirma para avisarle que estás bajando.',
                  style: TextStyle(
                    color: _riderMuted(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: acknowledged || busy ? null : _acknowledge,
            child: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(acknowledged ? 'Avisado' : 'Ya voy'),
          ),
        ],
      ),
    );
  }
}

class _TripActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _TripActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor:
            danger ? const Color(0xFFD92D20) : _riderText(context),
        side: BorderSide(
          color: danger
              ? const Color(0xFFF3B4AE)
              : _riderBorder(context),
        ),
        padding: const EdgeInsets.symmetric(vertical: 11),
      ),
      icon: Icon(icon, size: 18),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label),
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? detail;
  final String? rating;
  final VoidCallback onMap;
  final VoidCallback? onChat;
  final VoidCallback? onCall;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? dangerLabel;
  final VoidCallback? onDanger;

  const _ActiveCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onMap,
    this.detail,
    this.rating,
    this.onChat,
    this.onCall,
    this.primaryLabel,
    this.onPrimary,
    this.dangerLabel,
    this.onDanger,
  });

  @override
  Widget build(BuildContext context) {
    final extra = <String>[
      if (rating != null && rating!.trim().isNotEmpty) '★ ' + rating!,
      if (detail != null && detail!.trim().isNotEmpty) detail!,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1739), expressBlue],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                child: Icon(icon, color: expressBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFDCEAFF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (extra.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        extra.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFBFD8FF),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _ActiveAction(
                  icon: Icons.map_outlined,
                  label: 'Mapa',
                  onTap: onMap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActiveAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chat',
                  onTap: onChat,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActiveAction(
                  icon: Icons.phone_outlined,
                  label: 'Llamar',
                  onTap: onCall,
                ),
              ),
            ],
          ),
          if (primaryLabel != null || dangerLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (primaryLabel != null)
                  Expanded(
                    child: FilledButton(
                      onPressed: onPrimary,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: expressBlue,
                      ),
                      child: Text(primaryLabel!),
                    ),
                  ),
                if (primaryLabel != null && dangerLabel != null)
                  const SizedBox(width: 8),
                if (dangerLabel != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDanger,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0x99FFFFFF)),
                      ),
                      child: Text(dangerLabel!),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActiveAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActiveAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0x66FFFFFF)),
        padding: const EdgeInsets.symmetric(vertical: 11),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final surface = dark ? const Color(0xFF1E1E1E) : const Color(0xFFF8FAFC);
    final border = _riderBorder(context);
    final textColor = _riderText(context);
    final muted = _riderMuted(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFEAF2FF),
            child: Icon(icon, color: expressBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final IconData icon;
  final String route;
  final String fare;
  final String badge;
  final String button;
  final String? secondaryButton;
  final VoidCallback? onSecondary;
  final double? pickupDistanceKm;
  final double? routeDistanceKm;
  final int? routeDurationMinutes;
  final String? paymentMethod;
  final VoidCallback? onOpen;
  final VoidCallback onTap;

  const _JobCard({
    required this.icon,
    required this.route,
    required this.fare,
    required this.badge,
    required this.button,
    this.secondaryButton,
    this.onSecondary,
    this.pickupDistanceKm,
    this.routeDistanceKm,
    this.routeDurationMinutes,
    this.paymentMethod,
    this.onOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (pickupDistanceKm != null)
        pickupDistanceKm! < 1
            ? (pickupDistanceKm! * 1000).round().toString() + ' m al origen'
            : pickupDistanceKm!.toStringAsFixed(1) + ' km al origen',
      if (routeDistanceKm != null)
        routeDistanceKm!.toStringAsFixed(1) + ' km de viaje',
      if (routeDurationMinutes != null)
        routeDurationMinutes.toString() + ' min aprox.',
      if (paymentMethod != null) _paymentLabel(paymentMethod!),
    ];

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFEAF2FF),
                child: Icon(icon, color: expressBlue),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  route,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: expressDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fare,
                style: const TextStyle(
                  color: expressBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _JobInfoPill(
                icon: Icons.category_outlined,
                label: badge,
              ),
              for (final detail in details)
                _JobInfoPill(
                  icon: detail.contains('origen')
                      ? Icons.near_me_outlined
                      : detail.contains('km de viaje')
                          ? Icons.route_outlined
                          : detail.contains('min')
                              ? Icons.schedule_outlined
                              : Icons.payments_outlined,
                  label: detail,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (secondaryButton != null && onSecondary != null)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: onSecondary,
                      child: Text(secondaryButton!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: onTap,
                      child: Text(button),
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: onTap,
                child: Text(button),
              ),
            ),
        ],
      ),
    ),
    );
  }
}

class _JobInfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _JobInfoPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: expressMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: expressMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;
  final bool enabled;

  const _CircleButton({
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : .45,
      child: Material(
        elevation: 5,
        color: _riderHomeDark(context)
            ? const Color(0xFF151515)
            : Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: busy || !enabled ? null : onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    icon,
                    color: _riderHomeDark(context)
                        ? Colors.white
                        : expressDark,
                  ),
          ),
          ),
        ),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onPressed;
  final bool enabled;

  const _ModeBadge({
    required this.icon,
    required this.text,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : .45,
      child: Material(
        elevation: 5,
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        shadowColor: dark ? Colors.black87 : Colors.black26,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: dark ? const Color(0xFF79A8FF) : expressBlue, size: 18),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  color: _riderText(context),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.swap_horiz_rounded,
                size: 17,
                color: _riderMuted(context),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _OnlineBadge extends StatelessWidget {
  final bool approved;
  final bool online;
  final bool busy;
  final bool locked;
  final VoidCallback onPressed;

  const _OnlineBadge({
    required this.approved,
    required this.online,
    required this.busy,
    required this.locked,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final active = approved && online && !locked;
    return Material(
      elevation: 5,
      color: active ? const Color(0xFF12B76A) : Colors.white,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: busy || locked ? null : onPressed,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: active ? Colors.white : expressBlue,
                  ),
                )
              else
                Icon(
                  Icons.circle,
                  size: 10,
                  color: active ? Colors.white : const Color(0xFF98A2B3),
                ),
              const SizedBox(width: 6),
              Text(
                !approved
                    ? 'Pendiente'
                    : locked
                        // El conductor sigue conectado durante un servicio; solo
                        // el botón queda bloqueado. No mostrar "Fuera de línea".
                        ? (online ? 'En servicio' : 'Fuera de línea')
                        : busy
                            ? (online ? 'Desconectando…' : 'Activando…')
                            : active
                                ? 'En línea'
                                : 'Fuera de línea',
                style: TextStyle(
                  color: active ? Colors.white : expressDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapSearchRadar extends StatefulWidget {
  const _MapSearchRadar();

  @override
  State<_MapSearchRadar> createState() => _MapSearchRadarState();
}

class _MapSearchRadarState extends State<_MapSearchRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final radarColor = dark ? Colors.white : expressBlue;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size.square(224),
              painter: _RadarSweepPainter(
                progress: controller.value,
                color: radarColor,
              ),
            ),
            for (var i = 0; i < 3; i++)
              Builder(
                builder: (context) {
                  final progress = (controller.value + i / 3) % 1.0;
                  final fade =
                      (1.0 - progress).clamp(0.0, 1.0).toDouble();
                  return Transform.scale(
                    scale: .48 + progress * .68,
                    child: Container(
                      width: 204,
                      height: 204,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: radarColor.withValues(alpha: .025 * fade),
                        border: Border.all(
                          color: radarColor.withValues(alpha: .18 * fade),
                          width: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: radarColor.withValues(alpha: dark ? .055 : .04),
                border: Border.all(
                  color: radarColor.withValues(alpha: dark ? .11 : .13),
                ),
              ),
            ),
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: radarColor.withValues(alpha: dark ? .12 : .08),
                border: Border.all(
                  color: radarColor.withValues(alpha: dark ? .18 : .20),
                ),
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: expressBlue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 7,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RadarSweepPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RadarSweepPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .45;
    final rect = Rect.fromCircle(center: Offset.zero, radius: radius);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * 6.283185307179586);

    final sweep = Paint()
      ..color = color.withValues(alpha: .055)
      ..style = PaintingStyle.fill;
    canvas.drawArc(rect, -1.5707963267948966, .82, true, sweep);

    final line = Paint()
      ..color = color.withValues(alpha: .30)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(0, -radius), line);

    canvas.restore();

    final cross = Paint()
      ..color = color.withValues(alpha: .09)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      cross,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      cross,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _VehicleMapMarker extends StatefulWidget {
  final String vehicleType;
  final double orientation;
  final double scale;

  const _VehicleMapMarker({
    required this.vehicleType,
    this.orientation = 0,
    this.scale = 1,
  });

  @override
  State<_VehicleMapMarker> createState() => _VehicleMapMarkerState();
}

class _VehicleMapMarkerState extends State<_VehicleMapMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value - .5;
        return Transform.translate(
          offset: Offset(t * 2.4, -t.abs() * 1.8),
          child: Transform.scale(
            scale: widget.scale,
            child: Transform.rotate(
              angle: widget.orientation,
              child: child,
            ),
          ),
        );
      },
      child: Container(
        width: widget.vehicleType == 'motorcycle' ? 24 : 28,
        height: widget.vehicleType == 'motorcycle' ? 42 : 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: CustomPaint(
          painter: _TopDownVehiclePainter(
            vehicleType: widget.vehicleType,
            bodyColor: dark
                ? const Color(0xFFE5E7EB)
                : const Color(0xFFF8FAFC),
          ),
        ),
      ),
    );
  }
}

class _TopDownVehiclePainter extends CustomPainter {
  final String vehicleType;
  final Color bodyColor;

  const _TopDownVehiclePainter({
    required this.vehicleType,
    required this.bodyColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()..color = const Color(0x33000000);
    final body = Paint()..color = bodyColor;
    final dark = Paint()..color = const Color(0xFF475467);
    final glass = Paint()..color = const Color(0xFF98A2B3);
    final light = Paint()..color = const Color(0xFFDDE5EF);

    if (vehicleType == 'motorcycle') {
      // Moto Express: silueta compacta vista desde arriba.
      // El frente apunta hacia arriba; el widget rota este dibujo con
      // heading_degrees real del conductor.
      final cx = size.width / 2;
      final wheel = Paint()..color = const Color(0xFF111827);
      final metal = Paint()..color = const Color(0xFF64748B);
      final blue = Paint()..color = expressBlue;
      final blueDark = Paint()..color = const Color(0xFF073B8C);
      final seat = Paint()..color = const Color(0xFF1F2937);
      final lightPaint = Paint()..color = const Color(0xFFEAF2FF);

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + 1.2, size.height / 2 + 2.4),
          width: size.width * .48,
          height: size.height * .78,
        ),
        shadow,
      );

      // Ruedas delantera y trasera.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, size.height * .11),
            width: size.width * .20,
            height: size.height * .25,
          ),
          const Radius.circular(4),
        ),
        wheel,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, size.height * .89),
            width: size.width * .20,
            height: size.height * .25,
          ),
          const Radius.circular(4),
        ),
        wheel,
      );

      // Horquilla y manillar.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cx - size.width * .055,
            size.height * .17,
            size.width * .11,
            size.height * .16,
          ),
          const Radius.circular(3),
        ),
        metal,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cx - size.width * .31,
            size.height * .25,
            size.width * .62,
            size.height * .075,
          ),
          const Radius.circular(3),
        ),
        metal,
      );

      // Carenado azul Express.
      final fairing = ui.Path()
        ..moveTo(cx, size.height * .23)
        ..cubicTo(
          cx - size.width * .24,
          size.height * .31,
          cx - size.width * .25,
          size.height * .48,
          cx - size.width * .20,
          size.height * .62,
        )
        ..lineTo(cx - size.width * .13, size.height * .76)
        ..quadraticBezierTo(
          cx,
          size.height * .82,
          cx + size.width * .13,
          size.height * .76,
        )
        ..lineTo(cx + size.width * .20, size.height * .62)
        ..cubicTo(
          cx + size.width * .25,
          size.height * .48,
          cx + size.width * .24,
          size.height * .31,
          cx,
          size.height * .23,
        )
        ..close();
      canvas.drawPath(fairing, blue);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cx - size.width * .16,
            size.height * .45,
            size.width * .32,
            size.height * .28,
          ),
          Radius.circular(size.width * .12),
        ),
        seat,
      );

      // Parte trasera y luz frontal para que se entienda el sentido.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cx - size.width * .12,
            size.height * .70,
            size.width * .24,
            size.height * .14,
          ),
          const Radius.circular(4),
        ),
        blueDark,
      );
      canvas.drawCircle(
        Offset(cx, size.height * .27),
        size.width * .07,
        lightPaint,
      );
      return;
    }

    final isXl = vehicleType == 'xl';
    final bodyWidth = isXl ? size.width * .76 : size.width * .68;
    final bodyHeight = isXl ? size.height * .90 : size.height * .82;
    final left = (size.width - bodyWidth) / 2;
    final top = (size.height - bodyHeight) / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 2, top + 4, bodyWidth, bodyHeight),
        Radius.circular(isXl ? 9 : 11),
      ),
      shadow,
    );

    final wheelW = 4.5;
    final wheelH = 10.0;
    for (final y in [top + 9, top + bodyHeight - 19]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left - 2, y, wheelW, wheelH),
          const Radius.circular(2),
        ),
        dark,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left + bodyWidth - 2.5, y, wheelW, wheelH),
          const Radius.circular(2),
        ),
        dark,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, bodyWidth, bodyHeight),
        Radius.circular(isXl ? 9 : 11),
      ),
      body,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left + bodyWidth * .17,
          top + bodyHeight * .23,
          bodyWidth * .66,
          bodyHeight * .28,
        ),
        const Radius.circular(5),
      ),
      glass,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left + bodyWidth * .20,
          top + bodyHeight * .56,
          bodyWidth * .60,
          bodyHeight * .18,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF667085),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left + bodyWidth * .18,
          top + 3,
          bodyWidth * .64,
          4,
        ),
        const Radius.circular(2),
      ),
      light,
    );

    final tailPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(
      Offset(left + bodyWidth * .25, top + bodyHeight - 4.5),
      1.7,
      tailPaint,
    );
    canvas.drawCircle(
      Offset(left + bodyWidth * .75, top + bodyHeight - 4.5),
      1.7,
      tailPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TopDownVehiclePainter oldDelegate) {
    return oldDelegate.vehicleType != vehicleType ||
        oldDelegate.bodyColor != bodyColor;
  }
}

class _DemandPricingChip extends StatelessWidget {
  final Map<String, dynamic> quote;

  const _DemandPricingChip({required this.quote});

  @override
  Widget build(BuildContext context) {
    final multiplier = asDouble(quote['demand_multiplier']);
    final level = quote['demand_level']?.toString() ?? 'normal';

    final Color background;
    final Color foreground;
    final IconData icon;
    switch (level) {
      case 'low':
        background = const Color(0xFFEAF7EF);
        foreground = const Color(0xFF067647);
        icon = Icons.trending_down_rounded;
        break;
      case 'critical':
        background = const Color(0xFFFFE9E7);
        foreground = const Color(0xFFB42318);
        icon = Icons.local_fire_department_rounded;
        break;
      case 'high':
      case 'very_high':
        background = const Color(0xFFFFF0E5);
        foreground = const Color(0xFFB54708);
        icon = Icons.trending_up_rounded;
        break;
      case 'medium':
      case 'elevated':
        background = const Color(0xFFFFF7D6);
        foreground = const Color(0xFF8A6100);
        icon = Icons.bolt_rounded;
        break;
      default:
        background = const Color(0xFFEAF7EF);
        foreground = const Color(0xFF067647);
        icon = Icons.check_circle_rounded;
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foreground.withValues(alpha: .20)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 17),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              expressDemandMultiplierBadge(multiplier),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePointMapPin extends StatelessWidget {
  final String label;
  final Color background;

  const _RoutePointMapPin({
    required this.label,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 17,
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  final IconData icon;
  final bool dark;

  const _MapPin({
    required this.icon,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? expressDark : expressBlue,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _PassengerStateData {
  final ExpressService service;
  final Map<String, dynamic>? openRide;
  final Map<String, dynamic>? activeTrip;
  final Map<String, dynamic>? activeDelivery;
  final List<Map<String, dynamic>> offers;
  final List<Map<String, dynamic>> saved;
  final Map<String, dynamic>? counterpart;
  final Map<String, dynamic>? driverProfile;
  final Map<String, dynamic>? driverVehicle;
  final Map<String, dynamic>? pendingRating;
  final int viewedCount;
  final List<Map<String, dynamic>> viewers;
  final List<Map<String, dynamic>> nearbyDrivers;

  const _PassengerStateData({
    required this.service,
    this.openRide,
    this.activeTrip,
    this.activeDelivery,
    this.offers = const [],
    this.saved = const [],
    this.counterpart,
    this.driverProfile,
    this.driverVehicle,
    this.pendingRating,
    this.viewedCount = 0,
    this.viewers = const [],
    this.nearbyDrivers = const [],
  });
}

class _DriverStateData {
  final ExpressService service;
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> rides;
  final List<Map<String, dynamic>> deliveries;
  final Map<String, dynamic>? activeTrip;
  final Map<String, dynamic>? activeDelivery;
  final Map<String, dynamic>? counterpart;
  final Map<String, dynamic>? pendingRating;

  const _DriverStateData({
    required this.service,
    required this.profile,
    this.rides = const [],
    this.deliveries = const [],
    this.activeTrip,
    this.activeDelivery,
    this.counterpart,
    this.pendingRating,
  });
}

bool _isScheduledLater(Map<String, dynamic> ride) {
  final scheduled =
      DateTime.tryParse(ride['scheduled_for']?.toString() ?? '')?.toLocal();
  if (scheduled == null) return false;
  return scheduled.isAfter(DateTime.now().add(const Duration(minutes: 30)));
}

String _formatSchedule(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return day + '/' + month + '/' + local.year.toString() +
      ' · ' + hour + ':' + minute;
}

bool _expressIsParcelTrip(Map<String, dynamic> trip) {
  final ride = trip['ride_requests'];
  return ride is Map && ride['service_mode'] == 'parcel';
}

String? _driverTripNextLabel(String? status, {bool parcel = false}) {
  switch (status) {
    case 'driver_assigned':
      return parcel ? 'Llegué a recoger' : 'Llegué';
    case 'driver_arriving':
      return parcel ? 'Llegué a recoger' : 'Llegué';
    case 'driver_waiting':
      return parcel ? 'Confirmar recogida' : 'Iniciar viaje';
    case 'in_progress':
      return parcel ? 'Confirmar entrega' : 'Completar viaje';
    default:
      return null;
  }
}

String? _driverDeliveryNextLabel(String? status) {
  switch (status) {
    case 'accepted':
      return 'Paquete recogido';
    case 'picked_up':
      return 'Salir a entregar';
    case 'in_transit':
      return 'Marcar entregado';
    default:
      return null;
  }
}

String _parcelTripStatus(String? status) {
  switch (status) {
    case 'driver_assigned': return 'Repartidor asignado';
    case 'driver_arriving': return 'Camino a recoger paquete';
    case 'driver_waiting': return 'Esperando entrega del paquete';
    case 'in_progress': return 'Paquete en camino';
    case 'emergency': return 'Alerta en el envío';
    default: return status ?? 'Envío activo';
  }
}

String _tripStatus(String? value) {
  switch (value) {
    case 'driver_assigned':
      return 'Conductor asignado';
    case 'driver_arriving':
      return 'Conductor en camino';
    case 'driver_waiting':
      return 'Conductor esperando';
    case 'in_progress':
      return 'Viaje en curso';
    case 'emergency':
      return 'Alerta de emergencia';
    default:
      return value ?? 'Viaje activo';
  }
}

String _deliveryStatus(String? value) {
  switch (value) {
    case 'accepted':
      return 'Repartidor asignado';
    case 'picked_up':
      return 'Paquete recogido';
    case 'in_transit':
      return 'En camino';
    default:
      return value ?? 'Delivery activo';
  }
}

bool _riderHomeDark(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark;
}

Widget _expressMapTileLayer(BuildContext context) {
  final dark = _riderHomeDark(context);
  // Sin clave por tema: cambiar de tema no debe desmontar el mapa (las
  // teselas visibles se perderían hasta recargar).
  return ExpressBaseTileLayer(
    tileBuilder: dark ? darkModeTileBuilder : null,
  );
}

Color _riderText(BuildContext context) {
  return _riderHomeDark(context) ? Colors.white : expressDark;
}

Color _riderMuted(BuildContext context) {
  return _riderHomeDark(context)
      ? const Color(0xFF9CA3AF)
      : expressMuted;
}

Color _riderSurface(BuildContext context) {
  return _riderHomeDark(context)
      ? const Color(0xFF141414)
      : Colors.white;
}

Color _riderSoftSurface(BuildContext context) {
  return _riderHomeDark(context)
      ? const Color(0xFF1E1E1E)
      : const Color(0xFFF8FAFC);
}

Color _riderBorder(BuildContext context) {
  return _riderHomeDark(context)
      ? const Color(0xFF303030)
      : const Color(0xFFE4E7EC);
}

String _passengerGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Buenos días';
  if (hour < 20) return 'Buenas tardes';
  return 'Buenas noches';
}

String _paymentLabel(String value) {
  switch (value) {
    case 'driver_qr':
      return 'QR del conductor';
    case 'pagorut':
      return 'QR Bolivia';
    case 'mercado_pago':
      return 'Mercado Pago';
    case 'santander':
      return 'Banco Santander';
    case 'mach':
      return 'MACH';
    case 'tenpo':
      return 'Tenpo';
    case 'card':
      return 'Tarjeta';
    case 'wallet':
      return 'Billetera';
    default:
      return 'Efectivo';
  }
}

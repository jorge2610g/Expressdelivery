import 'express_offline_banner.dart';
import 'offline_status.dart';
import 'driver_floating_offers.dart';
import 'driver_floating_offer_focus.dart';
import 'driver_floating_offer_data.dart';
import 'dart:async';
import 'cancellation_fee_confirmation.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_error_reporter.dart';
import 'cancellation_debt_messages.dart';
import 'core/supabase_client.dart';
import 'core/runtime_channel.dart';
import 'connected_center.dart';
import 'driver_focus_navigation.dart';
import 'driver_realtime_scope.dart';
import 'driver_priority_page.dart';
import 'driver_championship_page.dart';
import 'driver_championship_visibility.dart';
import 'benefits_page.dart';
import 'express_account_pages.dart';
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
import 'map_vehicle_marker.dart';
import 'map_vehicle_heading.dart';
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

// Official Flutter panels reused by the public, backend-free presentation.
part 'express_moto_demo_widgets.dart';


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
  try {
    final route = await ExpressMapProvider.drivingRoute(
      from: from,
      to: to,
    );
    // The map provider returns a straight segment as its offline fallback.
    // Do not present that temporary segment as a road route.
    return route.provider == 'direct' || route.points.length < 2
        ? const <LatLng>[]
        : route.points;
  } catch (_) {
    return const <LatLng>[];
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
  return isExpressPlaceholderAddress(value);
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
  return fallback;
}

Future<String?> _expressReverseGeocodeAddress(LatLng point) async {
  try {
    return await ExpressMapProvider.reverseGeocodeLocationLabelCached(
      point: point,
    )
        .timeout(const Duration(seconds: 6));
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
    // A debt rejection is already translated by the action's caller. Showing
    // the generic transition error as well produces two alerts for one block.
    if (!isCancellationDebtBlockError(error)) {
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
    }
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
  final double? initialPickupLatitude;
  final double? initialPickupLongitude;
  final String? initialPickupLabel;
  final bool initialPickupIsManual;
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
    this.initialPickupLatitude,
    this.initialPickupLongitude,
    this.initialPickupLabel,
    this.initialPickupIsManual = false,
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
  LatLng? passengerLastMapFollowPoint;
  DateTime? passengerLastMapFollowAt;
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
  RealtimeChannel? passengerDriverLocationChannel;
  String? passengerDriverLocationTripId;
  String? passengerDriverLocationDriverId;
  int passengerDriverLocationRevision = 0;
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
      unawaited(syncDriverPushOverlayState(widget.service));
      unawaited(syncOverlayCallPreference(widget.service).then((granted) {
        if (mounted) setState(() => overlayAllowed = granted);
      }));
      // La sugerencia de sobreposición aparece al empezar un viaje, no al abrir la app.
    });
    serviceType = widget.initialServiceType == 'delivery' ? 'delivery' : 'ride';
    final initialLat = widget.initialPickupLatitude;
    final initialLng = widget.initialPickupLongitude;
    if (widget.initialPickupIsManual && initialLat != null &&
        initialLng != null && initialLat.isFinite && initialLng.isFinite) {
      pickup = PickedLocation(
        label: widget.initialPickupLabel?.trim().isNotEmpty == true
            ? widget.initialPickupLabel!.trim()
            : 'Ubicación seleccionada',
        latitude: initialLat,
        longitude: initialLng,
      );
      _pickupFromGps = false;
    }
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
      _syncPassengerDriverLocationRealtime(cachedData!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshHome();
      });
    } else {
      homeFuture = _load(++loadRevision);
    }

    _locate();
    _startPassengerMapFollow();
    if (pickup != null && !_pickupFromGps) {
      final selectedPickup = pickup!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pickupFromGps) return;
        _centerPassengerMap(
          LatLng(selectedPickup.latitude, selectedPickup.longitude),
          passengerMapZoom,
        );
      });
    }
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

  void _syncPassengerDriverLocationRealtime(_PassengerStateData data) {
    final trip = data.activeTrip;
    final tripId = trip == null ? null : trip['id']?.toString();
    final driverId = trip == null ? null : trip['driver_id']?.toString();
    final normalizedTripId = tripId?.trim();
    final normalizedDriverId = driverId?.trim();
    if (normalizedTripId == passengerDriverLocationTripId &&
        normalizedDriverId == passengerDriverLocationDriverId) return;

    final previous = passengerDriverLocationChannel;
    passengerDriverLocationChannel = null;
    passengerDriverLocationTripId = normalizedTripId;
    passengerDriverLocationDriverId = normalizedDriverId;
    if (previous != null) unawaited(supabase.removeChannel(previous));

    if (normalizedTripId == null || normalizedTripId.isEmpty ||
        normalizedDriverId == null || normalizedDriverId.isEmpty) return;
    final subscribedTripId = normalizedTripId;
    final subscribedDriverId = normalizedDriverId;
    passengerDriverLocationChannel = supabase
        .channel(
          'trip-location:$subscribedTripId',
          opts: const RealtimeChannelConfig(private: true),
        )
        .onBroadcast(
          event: 'driver_location',
          callback: (message) {
            if (!mounted ||
                passengerDriverLocationTripId != subscribedTripId ||
                passengerDriverLocationDriverId != subscribedDriverId) {
              return;
            }

            // Supabase Dart's onBroadcast callback already receives the
            // broadcast payload itself (not a Phoenix event envelope).
            final location = Map<String, dynamic>.from(message);
            if (location['trip_id']?.toString() != subscribedTripId ||
                location['driver_id']?.toString() != subscribedDriverId) {
              return;
            }

            final current = cachedData;
            if (current == null ||
                current.activeTrip?['id']?.toString() != subscribedTripId ||
                current.activeTrip?['driver_id']?.toString() !=
                    subscribedDriverId) {
              return;
            }

            final receivedAt = DateTime.tryParse(
              location['location_updated_at']?.toString() ?? '',
            )?.toUtc();
            final cachedAt = DateTime.tryParse(
              current.driverProfile?['location_updated_at']?.toString() ?? '',
            )?.toUtc();
            if (receivedAt != null && cachedAt != null &&
                cachedAt.isAfter(receivedAt)) return;

            passengerDriverLocationRevision++;

            // Apply only the live location fields. Profile details remain
            // sourced from the participant-scoped driver_profile_for_viewer RPC.
            final profile = <String, dynamic>{
              ...?current.driverProfile,
              if (location.containsKey('latitude'))
                'latitude': location['latitude'],
              if (location.containsKey('longitude'))
                'longitude': location['longitude'],
              if (location.containsKey('heading_degrees'))
                'heading_degrees': location['heading_degrees'],
              if (location.containsKey('location_updated_at'))
                'location_updated_at': location['location_updated_at'],
            };
            final next = _PassengerStateData(
              service: current.service,
              openRide: current.openRide,
              activeTrip: current.activeTrip,
              activeDelivery: current.activeDelivery,
              offers: current.offers,
              saved: current.saved,
              counterpart: current.counterpart,
              driverProfile: profile,
              driverVehicle: current.driverVehicle,
              pendingRating: current.pendingRating,
              viewedCount: current.viewedCount,
              viewers: current.viewers,
              nearbyDrivers: current.nearbyDrivers,
            );
            cachedData = next;
            homeFuture = Future.value(next);
            setState(() {});
          },
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
              ? preferredPayment
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
    String event = 'PASSENGER_TRIP_STATE_' + status.toUpperCase();

    switch (status) {
      case 'driver_assigned':
        title = 'Conductor confirmado';
        subtitle = 'Tu viaje ya tiene conductor asignado.';
        break;
      case 'driver_arriving':
        title = 'Tu conductor va en camino';
        subtitle = 'Puedes seguir su llegada directamente en el mapa.';
        break;
      case 'driver_waiting':
        title = 'Tu conductor llegó';
        subtitle = 'Ya se encuentra en el punto de recogida.';
        break;
      case 'in_progress':
        title = 'Viaje iniciado';
        subtitle = 'Tu viaje está en curso. Buen viaje.';
        break;
      case 'emergency':
        title = 'Alerta de emergencia activa';
        subtitle = 'Express registró el estado de emergencia del viaje.';
        break;
    }

    if (trip != null && _expressIsParcelTrip(trip)) {
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
        final locationRevisionAtRequest = passengerDriverLocationRevision;
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
        final latestState = cachedData;
        final latestDriverProfile =
            latestState?.activeTrip?['id']?.toString() == beforeActiveTripId
                ? latestState?.driverProfile
                : before.driverProfile;
        final nextDriverProfile = _retainNewerPassengerDriverLocation(
          mapOrNull(liveTrip['driver_profile']) ??
              before.driverProfile ??
              <String, dynamic>{},
          latestDriverProfile,
          preserveCachedLocation:
              passengerDriverLocationRevision != locationRevisionAtRequest,
        );

        final beforeLat = asDouble(before.driverProfile?['latitude']);
        final beforeLng = asDouble(before.driverProfile?['longitude']);
        final nextLat = asDouble(nextDriverProfile['latitude']);
        final nextLng = asDouble(nextDriverProfile['longitude']);
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
        _syncPassengerDriverLocationRealtime(next);
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

        // offersForRide ya devuelve conductor/perfil enriquecido. No lanzamos
        // passenger_home_state aquí: hacerlo inmediatamente podía competir con
        // este cambio visual y volver a pintar "Buscando conductor".
      } catch (_) {
        // Realtime y el refresco general siguen activos como respaldos.
      } finally {
        passengerOfferBootstrapInFlight = false;
      }
    }

    unawaited(checkNow());
    passengerOfferBootstrapTimer =
        Timer.periodic(const Duration(milliseconds: 1000), (pollTimer) {
      if (!mounted || passengerOfferRealtimeRideId != rideId) {
        pollTimer.cancel();
        if (identical(passengerOfferBootstrapTimer, pollTimer)) {
          passengerOfferBootstrapTimer = null;
        }
        return;
      }
      unawaited(checkNow());
    });
  }

  void _syncPassengerOfferRealtime(_PassengerStateData data) {
    String? rideId;
    if (data.activeTrip == null) {
      rideId = data.openRide?['id']?.toString();
    }

    if (rideId != passengerOfferOverlayRideId) {
      passengerOfferOverlayRideId = rideId;
      passengerOfferOverlayRide = null;
      passengerOfferOverlayOffers = <Map<String, dynamic>>[];
      passengerOfferPresentationActive = false;
      passengerOfferPresentationEpoch++;
    }

    if (rideId == passengerOfferRealtimeRideId) return;

    // Las exclusiones locales pertenecen únicamente a la solicitud actual.
    // Al cambiar de viaje se limpian para no bloquear futuras reofertas.
    locallyExpiredPassengerOfferKeys.clear();

    passengerOfferRealtimeDebounce?.cancel();
    passengerOfferRealtimeDebounce = null;
    unawaited(passengerOfferRealtimeSubscription?.cancel());
    passengerOfferRealtimeSubscription = null;
    passengerOfferRealtimeRideId = rideId;

    if (rideId == null || rideId.isEmpty) return;
    final subscribedRideId = rideId;

    passengerOfferRealtimeSubscription =
        widget.service.watchRideOffers(subscribedRideId).listen(
      (rows) {
        if (!mounted ||
            passengerOfferRealtimeRideId != subscribedRideId) {
          return;
        }

        // Pintar la oferta con los datos de Realtime inmediatamente.
        ExpressDiagnosticsHub.note(
          rows.isEmpty ? 'REALTIME_EMPTY' : 'OFFER_REALTIME_RECEIVED',
        );
        _applyRealtimePassengerOffers(
          subscribedRideId,
          rows,
          authoritative: false,
        );

        // El sondeo directo enriquece nombre/avatar en menos de un segundo.
        // No refrescamos todo el home aquí para no desmontar la presentación.
      },
      onError: (_) {
        // El sondeo periódico de 2 s queda como respaldo si Realtime se corta.
      },
    );

    // Respaldo inmediato para la primera oferta. Si el INSERT ocurre justo
    // mientras se establece el canal Realtime, esta lectura directa evita que
    // el pasajero tenga que esperar otro evento o tocar una notificación push.
    // Durante los primeros segundos de una solicitud hacemos una lectura
    // ligera cada segundo. Esto cubre la ventana en la que el canal Realtime
    // todavía se está estableciendo y garantiza que la primera oferta nunca
    // dependa de que el pasajero toque la notificación push.
    _startPassengerOfferBootstrapPoll(subscribedRideId);
  }

  void _applyRealtimePassengerOffers(
    String rideId,
    List<Map<String, dynamic>> rows, {
    required bool authoritative,
  }) {
    final currentData = cachedData;
    if (!mounted ||
        currentData == null ||
        currentData.activeTrip != null ||
        currentData.openRide?['id']?.toString() != rideId) {
      return;
    }

    final now = DateTime.now().toUtc();
    final previousById = <String, Map<String, dynamic>>{
      for (final offer in currentData.offers)
        if (offer['id']?.toString().isNotEmpty == true)
          offer['id'].toString(): offer,
    };

    final activeOffers = rows
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
        })
        .map((offer) {
          final id = offer['id']?.toString();
          final previous = id == null ? null : previousById[id];
          return <String, dynamic>{
            if (previous != null) ...previous,
            ...offer,
          };
        })
        .toList()
      ..sort((a, b) {
        final aTime =
            DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });

    // Realtime puede emitir [] durante la inicialización del stream.
    // Solo el feed directo autoritativo confirma una eliminación real.
    if (activeOffers.isEmpty && !authoritative) return;

    if (_samePassengerOfferList(currentData.offers, activeOffers)) return;

    final hadOffers = currentData.offers.isNotEmpty;

    // Barrera de carrera: una carga iniciada antes de este cambio ya no puede
    // terminar después y sobrescribir la oferta recién aplicada.
    loadRevision++;
    passengerOfferStateRevision++;

    if (hadOffers != activeOffers.isNotEmpty) {
      panelRevision++;
      passengerOfferPresentationEpoch++;
    }

    passengerOfferPresentationActive = activeOffers.isNotEmpty;
    passengerOfferOverlayRideId = rideId;
    passengerOfferOverlayRide = activeOffers.isNotEmpty && currentData.openRide != null
        ? Map<String, dynamic>.from(currentData.openRide!)
        : null;
    passengerOfferOverlayOffers = activeOffers
        .map((offer) => Map<String, dynamic>.from(offer))
        .toList();

    cachedData = _PassengerStateData(
      service: currentData.service,
      openRide: currentData.openRide,
      activeTrip: currentData.activeTrip,
      activeDelivery: currentData.activeDelivery,
      offers: activeOffers,
      saved: currentData.saved,
      counterpart: currentData.counterpart,
      driverProfile: currentData.driverProfile,
      driverVehicle: currentData.driverVehicle,
      pendingRating: currentData.pendingRating,
      viewedCount: currentData.viewedCount,
      viewers: currentData.viewers,
      nearbyDrivers: currentData.nearbyDrivers,
    );

    ExpressDiagnosticsHub.note(
      activeOffers.isEmpty ? 'OFFER_STATE_CLEARED' : 'OFFER_APPLIED_TO_STATE',
    );

    setState(() {
      homeFuture = Future.value(cachedData!);
    });

    if (activeOffers.isNotEmpty) {
      _ensurePassengerOfferVisible();
    }

    if (hadOffers && activeOffers.isEmpty) {
      _settlePassengerSearchSheetImmediately();
    }

    if (autoAcceptNearest && activeOffers.isNotEmpty) {
      _tryAutoAcceptOffers(activeOffers, currentData.openRide);
    }
  }

  void _refreshHome() {
    if (homeRefreshInFlight) {
      homeRefreshQueued = true;
      return;
    }
    final revision = ++loadRevision;
    homeRefreshInFlight = true;
    final nextFuture = _load(revision);
    setState(() {
      homeFuture = nextFuture;
    });

    // FutureBuilder is the consumer of nextFuture. A separate whenComplete()
    // creates a second Future that can surface the same network error as an
    // unhandled async exception. Consume that secondary path explicitly.
    unawaited(() async {
      try {
        await nextFuture;
        ExpressConnectivityMonitor.instance.recordSuccess('passenger_home');
      } catch (error) {
        ExpressConnectivityMonitor.instance.recordFailure(error);
        // The FutureBuilder keeps the visible error/result semantics.
      } finally {
        if (!mounted) return;
        homeRefreshInFlight = false;
        if (homeRefreshQueued) {
          homeRefreshQueued = false;
          _refreshHome();
        }
      }
    }());
  }

  void _refreshPassengerPendingRating(int revision) {
    if (passengerPendingRatingRefreshFuture != null) return;

    late final Future<void> refreshFuture;
    refreshFuture = () async {
      try {
        final pending = await widget.service.pendingRatingService();
        if (!mounted || revision != loadRevision) return;

        final currentData = cachedData;
        if (currentData == null) return;

        final currentId = currentData.pendingRating?['id']?.toString();
        final nextId = pending?['id']?.toString();
        final currentKind = currentData.pendingRating?['kind']?.toString();
        final nextKind = pending?['kind']?.toString();
        if (currentId == nextId && currentKind == nextKind) return;

        final updated = _PassengerStateData(
          service: currentData.service,
          openRide: currentData.openRide,
          activeTrip: currentData.activeTrip,
          activeDelivery: currentData.activeDelivery,
          offers: currentData.offers,
          saved: currentData.saved,
          counterpart: currentData.counterpart,
          driverProfile: currentData.driverProfile,
          driverVehicle: currentData.driverVehicle,
          pendingRating: pending,
          viewedCount: currentData.viewedCount,
          viewers: currentData.viewers,
          nearbyDrivers: currentData.nearbyDrivers,
        );
        cachedData = updated;
        homeFuture = Future.value(updated);
        setState(() {});
      } finally {
        if (identical(passengerPendingRatingRefreshFuture, refreshFuture)) {
          passengerPendingRatingRefreshFuture = null;
        }
      }
    }();

    passengerPendingRatingRefreshFuture = refreshFuture;
    unawaited(refreshFuture);
  }

  _PassengerStateData? _visiblePassengerData(_PassengerStateData? source) {
    if (source == null) return null;

    var openRide = source.openRide;
    var activeTrip = source.activeTrip;
    var activeDelivery = source.activeDelivery;

    final openRideId = openRide?['id']?.toString();
    if (openRideId != null && locallyCancelledRideIds.contains(openRideId)) {
      openRide = null;
    }

    if (activeTrip != null) {
      final tripId = activeTrip['id']?.toString();
      final rideRequestId = activeTrip['ride_request_id']?.toString() ??
          (activeTrip['ride_requests'] is Map
              ? (activeTrip['ride_requests'] as Map)['id']?.toString()
              : null);
      if ((tripId != null && locallyCancelledTripIds.contains(tripId)) ||
          (rideRequestId != null &&
              locallyCancelledRideIds.contains(rideRequestId))) {
        activeTrip = null;
      }
    }

    final deliveryId = activeDelivery?['id']?.toString();
    if (deliveryId != null &&
        locallyCancelledDeliveryIds.contains(deliveryId)) {
      activeDelivery = null;
    }

    var pendingRating = source.pendingRating;
    final pendingId = pendingRating?['id']?.toString();
    if (pendingId != null && locallyRatedPendingIds.contains(pendingId)) {
      pendingRating = null;
    }

    if (identical(openRide, source.openRide) &&
        identical(activeTrip, source.activeTrip) &&
        identical(activeDelivery, source.activeDelivery) &&
        identical(pendingRating, source.pendingRating)) {
      return source;
    }

    return _PassengerStateData(
      service: source.service,
      openRide: openRide,
      activeTrip: activeTrip,
      activeDelivery: activeDelivery,
      offers: openRide == null ? const [] : source.offers,
      saved: source.saved,
      counterpart:
          activeTrip == null && activeDelivery == null ? null : source.counterpart,
      driverProfile:
          activeTrip == null && activeDelivery == null ? null : source.driverProfile,
      driverVehicle:
          activeTrip == null ? null : source.driverVehicle,
      pendingRating: pendingRating,
      viewedCount: openRide == null ? 0 : source.viewedCount,
      viewers: openRide == null ? const [] : source.viewers,
      nearbyDrivers: source.nearbyDrivers,
    );
  }

  /// Centra [point] en el área del mapa que se ve por encima del panel inferior,
  /// bajo la barra de estado y la cabecera (no en el centro de la pantalla completa).
  void _centerPassengerMap(LatLng point, double zoom) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final occluded = sheetController.isAttached
        ? sheetController.size * size.height
        : _rideChooserSheetFraction(context) * size.height;
    final offset = visibleAreaCenterOffset(
      viewportHeight: size.height,
      topInset: MediaQuery.paddingOf(context).top + 72,
      bottomOccludedHeight: occluded,
    );
    try {
      mapController.move(point, zoom, offset: offset);
    } catch (_) {}
  }

  Map<String, dynamic> _retainNewerPassengerDriverLocation(
    Map<String, dynamic> incoming,
    Map<String, dynamic>? cached, {
    bool preserveCachedLocation = false,
  }) {
    if (cached == null) return incoming;
    final incomingAt = DateTime.tryParse(
      incoming['location_updated_at']?.toString() ?? '',
    )?.toUtc();
    final cachedAt = DateTime.tryParse(
      cached['location_updated_at']?.toString() ?? '',
    )?.toUtc();
    if (!preserveCachedLocation &&
        (incomingAt == null ||
            cachedAt == null ||
            !cachedAt.isAfter(incomingAt))) {
      return incoming;
    }

    return <String, dynamic>{
      ...incoming,
      for (final key in const [
        'latitude',
        'longitude',
        'heading_degrees',
        'location_updated_at',
      ])
        if (cached.containsKey(key)) key: cached[key],
    };
  }

  void _followPassengerActiveTrip(
    String stageKey,
    LatLng driverPoint,
    LatLng target,
  ) {
    final stageChanged = passengerMapTripStageKey != stageKey;
    final now = DateTime.now();
    final lastPoint = passengerLastMapFollowPoint;
    final elapsed = passengerLastMapFollowAt == null
        ? const Duration(days: 1)
        : now.difference(passengerLastMapFollowAt!);
    final movedKm = lastPoint == null
        ? double.infinity
        : (_pickupDistanceKm(
              lastPoint,
              driverPoint.latitude,
              driverPoint.longitude,
            ) ??
            double.infinity);

    // Keep the moving marker in view without continually interrupting map
    // tiles. The passenger map is non-draggable during an active trip.
    if (!stageChanged &&
        (movedKm < .05 || elapsed < const Duration(seconds: 10))) {
      return;
    }

    passengerMapTripStageKey = stageKey;
    passengerLastMapFollowPoint = driverPoint;
    passengerLastMapFollowAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([driverPoint, target]),
            padding: const EdgeInsets.fromLTRB(46, 170, 46, 330),
          ),
        );
      } catch (_) {}
    });
  }

  void _movePassengerSheet(double size) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !sheetController.isAttached) return;
      sheetController.animateTo(
        size,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _refreshPassengerActiveRoadRoute(
    String tripId,
    String status,
    LatLng driverPoint,
    LatLng target,
  ) {
    final key = tripId + ':' + status + ':' +
        (driverPoint.latitude * 1000).round().toString() + ':' +
        (driverPoint.longitude * 1000).round().toString();
    if (passengerActiveRoadRouteKey == key || passengerActiveRoadRouteLoading) {
      return;
    }
    passengerActiveRoadRouteLoading = true;
    unawaited(() async {
      final points = await _expressRoadRoute(driverPoint, target);
      if (!mounted) return;
      passengerActiveRoadRouteKey = key;
      passengerActiveRoadRouteLoading = false;
      setState(() => passengerActiveRoadRoute = points);
    }());
  }

  void _focusSearchCamera(Map<String, dynamic> ride) {
    final lat = asDouble(ride['pickup_latitude']);
    final lng = asDouble(ride['pickup_longitude']);
    if (lat == null || lng == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // During driver search the pickup + radar + nearby vehicles are the
      // important context. Keep them above the compact bottom sheet.
      _centerPassengerMap(LatLng(lat, lng), 14.6);
    });
  }

  void _fitRouteCamera({double panelFraction = .50}) {
    final from = pickup;
    final to = destination;
    if (from == null || to == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final points = roadRoute.length >= 2
          ? roadRoute
          : <LatLng>[
              LatLng(from.latitude, from.longitude),
              LatLng(to.latitude, to.longitude),
            ];

      var minLat = points.first.latitude;
      var maxLat = points.first.latitude;
      var minLng = points.first.longitude;
      var maxLng = points.first.longitude;
      for (final point in points.skip(1)) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      final screenHeight = MediaQuery.sizeOf(context).height;
      final bottomPadding =
          (screenHeight * panelFraction + 78).clamp(320.0, screenHeight * .74);

      mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat, minLng),
            LatLng(maxLat, maxLng),
          ),
          // Margen superior mayor: la píldora de demanda no debe tapar el pin B.
          padding: EdgeInsets.fromLTRB(
            46,
            170,
            46,
            bottomPadding.toDouble(),
          ),
        ),
      );
    });
  }

  void _reportPassengerFlowState(bool active) {
    if (lastReportedPassengerFlowActive == active) return;
    lastReportedPassengerFlowActive = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFlowStateChanged?.call(active);
    });
  }

  bool _passengerTripNavigationLocked(Map<String, dynamic>? trip) {
    if (trip == null) return false;
    return const <String>{
      'driver_assigned',
      'driver_arriving',
      'driver_waiting',
      'in_progress',
      'emergency',
    }.contains(trip['status']?.toString());
  }

  void _reportPassengerTripNavigationLock(bool locked) {
    if (lastReportedTripNavigationLock == locked) return;
    lastReportedTripNavigationLock = locked;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTripNavigationLockChanged?.call(locked);
    });
  }

  void _backFromPassengerSetup() {
    if (!_pickupFromGps && pickup != null) {
      final point = LatLng(pickup!.latitude, pickup!.longitude);
      setState(() {
        passengerFlowMinimized = false;
        destination = null;
        routeConfirmed = false;
        scheduledFor = null;
        routeDistanceKm = null;
        routeDurationMinutes = null;
        roadRoute = const [];
        fareManuallyEdited = false;
        fareQuote = const <String, dynamic>{};
        ++fareQuoteEpoch;
        quoting = false;
      });
      _movePassengerSheet(.42);
      passengerMapZoom = 14.6;
      _centerPassengerMap(point, passengerMapZoom);
      return;
    }

    final point = current;
    setState(() {
      passengerFlowMinimized = false;
      destination = null;
      routeConfirmed = false;
      scheduledFor = null;
      routeDistanceKm = null;
      routeDurationMinutes = null;
      roadRoute = const [];
      fareManuallyEdited = false;
      fareQuote = const <String, dynamic>{};
      ++fareQuoteEpoch;
      quoting = false;
      _pickupFromGps = point != null;
      pickup = point == null
          ? null
          : PickedLocation(
              label: 'Mi ubicación actual',
              latitude: point.latitude,
              longitude: point.longitude,
            );
    });
    _movePassengerSheet(.42);
    if (point != null) {
      passengerMapZoom = 14.6;
      _centerPassengerMap(point, passengerMapZoom);
    }

    // Si el origen era GPS, actualizamos el punto para el siguiente viaje.
    // Un origen manual ya salió arriba y se conserva al volver al mapa.
    unawaited(_locate(resetPickupToGps: true));
  }

  void _backFromPassengerFlow() {
    if (_passengerTripNavigationLocked(cachedData?.activeTrip)) {
      _reportPassengerTripNavigationLock(true);
      return;
    }
    final hasBackendFlow = creating ||
        cachedData?.openRide != null ||
        cachedData?.activeTrip != null ||
        cachedData?.activeDelivery != null ||
        passengerLiveOfferRide != null ||
        passengerOfferOverlayRide != null;
    if (!hasBackendFlow) {
      _backFromPassengerSetup();
      return;
    }
    setState(() => passengerFlowMinimized = true);
    _reportPassengerFlowState(false);
  }

  void _restorePassengerFlow() {
    setState(() => passengerFlowMinimized = false);
  }

  // Sigue el GPS local sin consultar el backend ni sobrescribir un origen manual.
  void _startPassengerMapFollow() {
    passengerMapPositionSubscription?.cancel();
    passengerMapPositionSubscription = locationService
        .positionStream(highFrequency: false)
        .listen((position) {
      if (!mounted || locating || !position.latitude.isFinite ||
          !position.longitude.isFinite) return;
      final point = LatLng(position.latitude, position.longitude);
      final now = DateTime.now();
      final elapsed = lastPassengerCameraMoveAt == null
          ? const Duration(minutes: 1)
          : now.difference(lastPassengerCameraMoveAt!);
      final old = current;
      final meters = old == null ? double.infinity :
          locationService.distanceMeters(
            fromLatitude: old.latitude,
            fromLongitude: old.longitude,
            toLatitude: point.latitude,
            toLongitude: point.longitude,
          );
      current = point;
      final hasRoute = cachedData?.activeTrip != null ||
          cachedData?.activeDelivery != null ||
          cachedData?.openRide != null || destination != null;
      if (!hasRoute && _pickupFromGps &&
          elapsed >= const Duration(seconds: 2) &&
          (meters >= 12 || elapsed >= const Duration(seconds: 12))) {
        lastPassengerCameraMoveAt = now;
        _centerPassengerMap(point, passengerMapZoom);
      }
    }, onError: (_) {});
  }

  Future<void> _locate({bool resetPickupToGps = false}) async {
    if (locating) return;
    setState(() => locating = true);

    LatLng? cachedPoint;
    try {
      // Paint the map immediately from the last local fix. This never calls
      // the backend and avoids a blank/blocked first frame while GPS warms up.
      if (!resetPickupToGps) {
        final cached = await locationService.cachedPosition(
          maxAge: ExpressLocationService.persistentFallbackMaxAge,
        );
        if (cached != null && mounted) {
          cachedPoint = LatLng(cached.latitude, cached.longitude);
          final shouldResetPickup = pickup == null || _pickupFromGps;
          setState(() {
            current = cachedPoint;
            if (shouldResetPickup) {
              _pickupFromGps = true;
              pickup = PickedLocation(
                label: 'Mi ubicación actual',
                latitude: cached.latitude,
                longitude: cached.longitude,
              );
            }
          });
          if (shouldResetPickup) {
            passengerMapZoom = 14.6;
            mapController.move(cachedPoint, passengerMapZoom);
          }

          // Even with an initialZone, resolve the currency/services once from
          // this cached pickup coordinate. The initial landing can be an old
          // Bolivia snapshot while the passenger is already in Iquique.
          // Run in the background: show the map immediately, without waiting
          // for a network round-trip before requesting fresh GPS.
          final servicePoint = pickup;
          unawaited(_loadRideServices(
            latitude: servicePoint?.latitude ?? cached.latitude,
            longitude: servicePoint?.longitude ?? cached.longitude,
          ));
        }
      }

      // A visible map deserves a precise fresh fix. It runs after the cached
      // point is already on screen, so precision no longer blocks the UI.
      final position = await locationService.currentPosition(
        allowCachedFallback: false,
      );
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      final movedMeters = cachedPoint == null
          ? double.infinity
          : locationService.distanceMeters(
              fromLatitude: cachedPoint.latitude,
              fromLongitude: cachedPoint.longitude,
              toLatitude: position.latitude,
              toLongitude: position.longitude,
            );
      // The startup cache can be from another place. While the origin is still
      // the automatic GPS point, the fresh fix replaces it.
      final previousPickup = pickup;
      final shouldResetPickup =
          resetPickupToGps || pickup == null || _pickupFromGps;
      setState(() {
        current = point;
        if (shouldResetPickup) {
          _pickupFromGps = true;
          pickup = PickedLocation(
            label: 'Mi ubicación actual',
            latitude: position.latitude,
            longitude: position.longitude,
          );
        }
      });

      if (shouldResetPickup) {
        passengerMapZoom = 14.6;
        _centerPassengerMap(point, passengerMapZoom);
      }

      // Do not re-query zone/services for tiny GPS corrections.
      if (resetPickupToGps ||
          activeZone == null ||
          cachedPoint == null ||
          movedMeters >= 200) {
        final servicePoint = pickup;
        await _loadRideServices(
          latitude: servicePoint?.latitude ?? position.latitude,
          longitude: servicePoint?.longitude ?? position.longitude,
        );
      }

      // Si el usuario pulsa el botón de centrar después de haber elegido un
      // origen manual, el GPS vuelve a ser el origen del viaje y la ruta se
      // recalcula con ese punto real.
      final pickupMoved = shouldResetPickup &&
          (previousPickup == null ||
              previousPickup.latitude != position.latitude ||
              previousPickup.longitude != position.longitude);
      if ((resetPickupToGps || pickupMoved) && destination != null) {
        await _fitRoute();
      }

      // La primera carga ocurre antes de resolver el GPS. Refrescamos en
      // cuanto ya conocemos la posición para poblar los vehículos cercanos.
      _refreshHome();
    } catch (_) {
      // El mapa conserva la última ubicación local aunque el GPS fresco falle.
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> _pickPickup() async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: 'Seleccionar origen',
          initialLabel: pickup?.label,
          initialLatitude: pickup?.latitude,
          initialLongitude: pickup?.longitude,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pickupFromGps = false;
      pickup = result;
      routeConfirmed = false;
    });
    await _loadRideServices(
      latitude: result.latitude,
      longitude: result.longitude,
    );
    final confirmFraction = _routeConfirmationSheetFraction(context);
    _movePassengerSheet(confirmFraction);
    await _fitRoute();
  }

  Future<void> _pickDestination() async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: serviceType == 'delivery'
              ? 'Dirección de entrega'
              : '¿A dónde vas?',
          initialLabel: destination?.label,
          initialLatitude: destination?.latitude,
          initialLongitude: destination?.longitude,
          forbiddenLatitude: pickup?.latitude,
          forbiddenLongitude: pickup?.longitude,
          forbiddenMessage:
              'No puedes usar la misma ubicación como origen y destino. Selecciona otra ubicación.',
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      passengerFlowMinimized = false;
      destination = result;
      routeConfirmed = false;
    });
    final confirmFraction = _routeConfirmationSheetFraction(context);
    _movePassengerSheet(confirmFraction);
    await _fitRoute();
  }

  Future<void> _fitRoute() async {
    final a = pickup;
    final b = destination;
    if (a == null || b == null) {
      if (mounted) {
        setState(() {
          roadRoute = const [];
          routeDistanceKm = null;
          routeDurationMinutes = null;
        });
      }
      return;
    }

    final from = LatLng(a.latitude, a.longitude);
    final to = LatLng(b.latitude, b.longitude);

    _fitRouteCamera(
      panelFraction: _routeConfirmationSheetFraction(context),
    );

    final directMeters = const Distance().as(
      LengthUnit.Meter,
      from,
      to,
    );
    final fallbackKm = directMeters / 1000;
    final fallbackMinutes =
        (fallbackKm / 30 * 60).clamp(1, 240).round();

    setState(() {
      routing = true;
      fareManuallyEdited = false;
      routeDistanceKm = fallbackKm;
      routeDurationMinutes = fallbackMinutes;
      roadRoute = const <LatLng>[];
    });

    try {
      final route = await ExpressMapProvider.drivingRoute(
        from: from,
        to: to,
      );

      if (mounted) {
        setState(() {
          roadRoute = route.provider == 'direct' || route.points.length < 2
              ? const <LatLng>[]
              : route.points;
          if (route.distanceMeters != null) {
            routeDistanceKm = route.distanceMeters! / 1000;
          }
          if (route.durationSeconds != null) {
            routeDurationMinutes =
                (route.durationSeconds! / 60).clamp(1, 1440).round();
          }
        });
      }

      _fitRouteCamera(
        panelFraction: routeConfirmed
            ? _rideChooserSheetFraction(context)
            : _routeConfirmationSheetFraction(context),
      );
    } catch (_) {
      // Keep the fare estimate but do not draw a misleading straight route.
    } finally {
      if (mounted) {
        setState(() => routing = false);
        if (routeConfirmed) {
          await _refreshFareQuote();
        }
      }
    }
  }

  bool _confirmRouteInFlight = false;

  Future<void> _confirmRoute() async {
    // Un doble toque en "Confirmar" no debe iniciar dos flujos: `routing` solo
    // se activa dentro de _fitRoute, después de las consultas de cobertura.
    if (_confirmRouteInFlight) return;
    _confirmRouteInFlight = true;
    try {
      await _confirmRouteBody();
    } finally {
      _confirmRouteInFlight = false;
    }
  }

  Future<void> _confirmRouteBody() async {
    final from = pickup;
    final to = destination;
    if (from == null || to == null || routing) return;

    try {
      final policies = await Future.wait([
        widget.service.geoPolicy(
          latitude: from.latitude,
          longitude: from.longitude,
          audience: 'passenger',
        ),
        widget.service.geoPolicy(
          latitude: to.latitude,
          longitude: to.longitude,
          audience: 'passenger',
        ),
      ]).timeout(const Duration(seconds: 4));

      if (!mounted) return;

      final pickupPolicy = policies[0];
      final destinationPolicy = policies[1];
      final pickupOutside = pickupPolicy['coverage_enforced'] == true &&
          pickupPolicy['inside_coverage'] == false;
      final destinationOutside =
          destinationPolicy['coverage_enforced'] == true &&
              destinationPolicy['inside_coverage'] == false;

      if (pickupOutside || destinationOutside) {
        final point = pickupOutside ? 'origen' : 'destino';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'El $point está fuera de la zona de cobertura configurada por Express.',
            ),
          ),
        );
        return;
      }

      List<Map<String, dynamic>> zones(Object? raw) {
        if (raw is! List) return const <Map<String, dynamic>>[];
        return raw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }

      final warnings = <Map<String, dynamic>>[
        ...zones(pickupPolicy['security_zones']).map(
          (row) => <String, dynamic>{...row, 'route_point': 'Origen'},
        ),
        ...zones(destinationPolicy['security_zones']).map(
          (row) => <String, dynamic>{...row, 'route_point': 'Destino'},
        ),
      ];

      if (warnings.isNotEmpty) {
        final continueTrip = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                icon: const Icon(
                  Icons.health_and_safety_outlined,
                  color: Color(0xFFF79009),
                  size: 34,
                ),
                title: const Text('Aviso de seguridad'),
                content: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Uno de los puntos del recorrido requiere especial precaución.',
                      ),
                      const SizedBox(height: 12),
                      for (final warning in warnings)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7E8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFF7D9A5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (warning['route_point'] ?? '').toString() +
                                    ' · ' +
                                    (warning['name'] ?? 'Zona de precaución')
                                        .toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (warning['message']?.toString().trim().isNotEmpty ==
                                  true) ...[
                                const SizedBox(height: 3),
                                Text(
                                  warning['message'].toString(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cambiar ruta'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Continuar'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!continueTrip || !mounted) return;
      }
    } catch (_) {
      // Si la política geográfica no responde, no bloqueamos al usuario.
      // El mapa/radio existentes permanecen como respaldo.
    }

    setState(() {
      routeConfirmed = true;
      // First-frame fare=5 is not a valid Chile quote. Keep the chooser
      // pending until the backend returns the fare for these coordinates.
      quoting = true;
      fareQuote = const <String, dynamic>{};
      fareManuallyEdited = false;
    });
    final chooserFraction = _rideChooserSheetFraction(context);
    _movePassengerSheet(chooserFraction);
    _fitRouteCamera(panelFraction: chooserFraction);
    await _refreshFareQuote();
  }

  Future<void> _refreshFareQuote() async {
    final distance = routeDistanceKm;
    final duration = routeDurationMinutes;
    final origin = pickup;
    final serviceKey = category;
    if (destination == null || distance == null || duration == null) return;

    final oldCurrency = fareQuote['currency']?.toString().toUpperCase();
    final requestEpoch = ++fareQuoteEpoch;
    setState(() {
      quoting = true;
      // Do not display old fare/currency during a new server calculation.
      fareQuote = const <String, dynamic>{};
    });
    try {
      final quote = origin == null
          ? await widget.service.quoteFare(
              serviceKey: serviceKey,
              distanceKm: distance,
              durationMinutes: duration,
              previewDemand: expressPreviewDemandMode,
            )
          : await widget.service.quoteServiceFareForLocation(
              serviceKey: serviceKey,
              distanceKm: distance,
              durationMinutes: duration,
              latitude: origin.latitude,
              longitude: origin.longitude,
            );

      if (!mounted || requestEpoch != fareQuoteEpoch ||
          !routeConfirmed || category != serviceKey) return;
      final recommended = asDouble(quote['minimum_allowed_fare']) ??
          asDouble(quote['recommended_fare']) ??
          asDouble(quote['amount']);
      if (!passengerRideFareIsReady(quote) ||
          recommended == null || recommended <= 0) {
        return; // Show retry, never expose the default 5 as a valid quote.
      }

      setState(() {
        fareQuote = Map<String, dynamic>.from(quote);
        // An offer edited in BOB must not be carried into a CLP trip.
        if (oldCurrency != null &&
            oldCurrency != quote['currency']?.toString().toUpperCase()) {
          fareManuallyEdited = false;
        }
        if (!fareManuallyEdited || fare.toDouble() < recommended) {
          fare = recommended;
        }
      });
    } catch (_) {
      // If network/quote fails, the chooser displays retry and Confirm stays
      // disabled. We never silently publish the default fallback fare.
    } finally {
      if (mounted && requestEpoch == fareQuoteEpoch) {
        setState(() => quoting = false);
      }
    }
  }

  void _observePassengerCompletion(_PassengerStateData? data) {
    // Una calificación histórica no puede parecer un viaje recién terminado.
    // Si ya hay una nueva búsqueda o un viaje activo, no mostramos este banner.
    if (data?.openRide != null || data?.activeTrip != null) return;

    final pending = data?.pendingRating;
    if (pending == null || pending['kind']?.toString() != 'trip') return;
    final tripId = pending['id']?.toString();
    if (tripId == null || tripId == lastAnimatedPassengerCompletedTripId) return;

    // Solo mostramos la transición final si veníamos siguiendo exactamente
    // este viaje y su último estado visible era "in_progress".
    final trackedId = lastAnimatedPassengerTripId;
    if (trackedId != tripId || lastAnimatedPassengerTripStatus != 'in_progress') {
      return;
    }

    // Se reclama justo antes de mostrar: una comprobación previa que no aplica
    // no debe consumir la única calificación automática del viaje.
    if (!passengerRatingPromptGate.claim(tripId)) return;
    lastAnimatedPassengerCompletedTripId = tripId;
    unawaited(
      AppErrorReporter.event(
        'PASSENGER_TRIP_COMPLETED',
        source: 'ride_state_change',
        screen: 'passenger_home',
      ),
    );

    // El pasajero debe poder calificar inmediatamente al conductor cuando
    // desaparece el viaje activo. Se agenda fuera del build para no abrir un
    // diálogo durante la construcción del widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentPending = cachedData?.pendingRating;
      if (currentPending?['id']?.toString() != tripId) return;
      unawaited(_ratePending(currentPending!));
    });
  }

  Future<void> _ratePending(Map<String, dynamic> pending) async {
    final saved = await showExpressRatingDialog(
      context,
      widget.service,
      pending,
      counterpartLabel: 'conductor',
    );
    if (saved && mounted) {
      final ratedId = pending['id']?.toString();
      if (ratedId != null && ratedId.isNotEmpty) {
        locallyRatedPendingIds.add(ratedId);
      }
      final current = cachedData;
      if (current != null) {
        final cleared = _PassengerStateData(
          service: current.service,
          openRide: current.openRide,
          activeTrip: current.activeTrip,
          activeDelivery: current.activeDelivery,
          offers: current.offers,
          saved: current.saved,
          counterpart: current.counterpart,
          driverProfile: current.driverProfile,
          driverVehicle: current.driverVehicle,
          pendingRating: null,
          viewedCount: current.viewedCount,
          viewers: current.viewers,
          nearbyDrivers: current.nearbyDrivers,
        );
        cachedData = cleared;
        homeFuture = Future.value(cleared);
        setState(() {});
      }
      _refreshHome();
      widget.onChanged();
    }
  }

  List<Map<String, dynamic>> _compatibleCachedNearbyDrivers(
    String? requestedVehicleType,
  ) {
    final previous =
        cachedData?.nearbyDrivers ?? const <Map<String, dynamic>>[];
    final lastNonEmptyAt = nearbyDriversLastNonEmptyAt;
    if (previous.isEmpty || lastNonEmptyAt == null) {
      return <Map<String, dynamic>>[];
    }
    if (DateTime.now().difference(lastNonEmptyAt) >
        _nearbyDriversStaleGrace) {
      return <Map<String, dynamic>>[];
    }

    final requested = requestedVehicleType?.trim().toLowerCase();
    if (requested == null || requested.isEmpty || requested == 'any') {
      return previous
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }

    return previous
        .where(
          (row) =>
              row['vehicle_type']?.toString().trim().toLowerCase() ==
              requested,
        )
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<_PassengerStateData> _load(int revision) async {
    final state = await widget.service.passengerHomeState();

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

    // Rating is secondary UI. Do not block trips/offers while its extra
    // configuration/RPC/existence checks are running.
    final pendingRating = cachedData?.pendingRating;
    final rawOpenRide = mapOrNull(state['open_ride']);
    final rawActiveTrip = mapOrNull(state['active_trip']);
    final rawActiveDelivery = mapOrNull(state['active_delivery']);

    var openRide = rawOpenRide;
    var activeTrip = passengerFinishedTrips.visibleActiveTrip(rawActiveTrip);
    var activeDelivery = rawActiveDelivery;

    final openRideId = openRide?['id']?.toString();
    if ((openRideId != null && locallyCancelledRideIds.contains(openRideId)) ||
        openRideId == cancellingRideId) {
      openRide = null;
    }

    final activeTripId = activeTrip?['id']?.toString();
    final activeTripRideId = activeTrip?['ride_request_id']?.toString() ??
        (activeTrip?['ride_requests'] is Map
            ? (activeTrip!['ride_requests'] as Map)['id']?.toString()
            : null);
    if ((activeTripId != null &&
            locallyCancelledTripIds.contains(activeTripId)) ||
        (activeTripRideId != null &&
            locallyCancelledRideIds.contains(activeTripRideId)) ||
        activeTripId == cancellingTripId) {
      activeTrip = null;
    }

    final activeDeliveryId = activeDelivery?['id']?.toString();
    if ((activeDeliveryId != null &&
            locallyCancelledDeliveryIds.contains(activeDeliveryId)) ||
        activeDeliveryId == cancellingDeliveryId) {
      activeDelivery = null;
    }

    final rideCancellationConfirmed = cancellingRideId != null &&
        rawOpenRide?['id']?.toString() != cancellingRideId;
    final tripCancellationConfirmed = cancellingTripId != null &&
        rawActiveTrip?['id']?.toString() != cancellingTripId;
    final deliveryCancellationConfirmed = cancellingDeliveryId != null &&
        rawActiveDelivery?['id']?.toString() != cancellingDeliveryId;

    final now = DateTime.now().toUtc();
    var activeOffers = listOfMaps(state['offers']).where((offer) {
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

    // Un RPC más lento no debe borrar una oferta que ya llegó por la tabla
    // directa/Reatime. Conservamos solo ofertas aún vigentes y del mismo viaje.
    final previousData = cachedData;
    if (activeOffers.isEmpty &&
        openRide != null &&
        activeTrip == null &&
        previousData?.openRide?['id']?.toString() ==
            openRide['id']?.toString()) {
      activeOffers = previousData!.offers.where((offer) {
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
    }

    // Las ofertas son información crítica para la interacción. Se pintan
    // inmediatamente después de passenger_home_state, sin esperar consultas
    // secundarias (vehículos cercanos, vistas, etc.).
    if (revision == loadRevision &&
        openRide != null &&
        activeTrip == null &&
        activeOffers.isNotEmpty) {
      final previous = cachedData;
      final quickState = _PassengerStateData(
        service: widget.service,
        openRide: openRide,
        activeTrip: activeTrip,
        activeDelivery: activeDelivery,
        offers: activeOffers,
        saved: listOfMaps(state['saved']),
        counterpart: mapOrNull(state['counterpart']),
        driverProfile: mapOrNull(state['driver_profile']),
        pendingRating: pendingRating,
        viewedCount: previous?.viewedCount ?? 0,
        viewers: previous?.viewers ?? const [],
        nearbyDrivers: previous?.nearbyDrivers ?? const [],
      );
      if (!_samePassengerOfferList(
        cachedData?.offers ?? const <Map<String, dynamic>>[],
        activeOffers,
      )) {
        passengerOfferStateRevision++;
      }
      cachedData = quickState;
      passengerOfferPresentationActive = activeOffers.isNotEmpty;
      _syncPassengerOfferRealtime(quickState);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || revision != loadRevision) return;
        setState(() {});
      });
    }

    var driverProfile = mapOrNull(state['driver_profile']);
    Map<String, dynamic>? driverVehicle;
    if (activeTrip != null) {
      final driverId = activeTrip['driver_id']?.toString();
      if (driverId != null && driverId.isNotEmpty) {
        try {
          driverProfile =
              await widget.service.driverProfileById(driverId) ?? driverProfile;
        } catch (_) {}
        try {
          driverVehicle = await widget.service.driverVehicleById(driverId);
        } catch (_) {}
      }
    }

    var viewedCount = 0;
    var viewers = <Map<String, dynamic>>[];
    var nearbyDrivers = <Map<String, dynamic>>[];

    if (openRide != null) {
      final rideId = openRide['id']?.toString();
      if (rideId != null && rideId.isNotEmpty) {
        try {
          viewedCount = await widget.service.rideRequestViewCount(rideId);
          viewers = await widget.service.rideRequestViewers(rideId);
        } catch (_) {}
      }
    }

    // Mostrar vehículos disponibles también en el mapa principal, antes de
    // crear una solicitud. Se usa el origen seleccionado y, como respaldo,
    // la ubicación GPS actual del pasajero.
    final markerLat = asDouble(openRide?['pickup_latitude']) ??
        pickup?.latitude ??
        current?.latitude;
    final markerLng = asDouble(openRide?['pickup_longitude']) ??
        pickup?.longitude ??
        current?.longitude;
    String? requestedVehicleType;
    if (markerLat != null && markerLng != null) {
      try {
        final effectiveCategory =
            openRide?['category']?.toString() ?? category;
        Map<String, dynamic>? configuredService;
        for (final service in rideServices) {
          if (service['service_key']?.toString() == effectiveCategory) {
            configuredService = service;
            break;
          }
        }
        final configuredVehicle =
            configuredService?['vehicle_type']?.toString();
        requestedVehicleType = (openRide == null && !routeConfirmed) ||
                widget.service.runtimeChannel == 'preview'
            ? null
            : configuredVehicle == 'any'
                ? null
                : configuredVehicle ??
                    (effectiveCategory == 'motocar'
                        ? 'motocar'
                        : effectiveCategory == 'motorcycle'
                        ? 'motorcycle'
                        : effectiveCategory == 'xl'
                            ? 'xl'
                            : 'car');

        final compatibleCached =
            _compatibleCachedNearbyDrivers(requestedVehicleType);
        final sameRequestedType =
            nearbyDriversLastRequestedType == requestedVehicleType;

        final fetchedDrivers =
            await widget.service.nearbyOnlineDriverMarkers(
          latitude: markerLat,
          longitude: markerLng,
          radiusKm: asDouble(runtimeSettings['max_driver_request_radius_km']) ??
              10,
          vehicleType: requestedVehicleType,
        );

        if (fetchedDrivers.isNotEmpty) {
          nearbyDrivers = fetchedDrivers;
          nearbyDriversLastNonEmptyAt = DateTime.now();
          nearbyDriversLastRequestedType = requestedVehicleType;
        } else if (sameRequestedType && compatibleCached.isNotEmpty) {
          // Una respuesta vacía aislada no borra de golpe todos los vehículos.
          // Si sigue vacía durante la ventana de gracia, el siguiente refresh
          // sí terminará limpiando la lista.
          nearbyDrivers = compatibleCached;
        } else {
          nearbyDrivers = fetchedDrivers;
          nearbyDriversLastRequestedType = requestedVehicleType;
        }

        // En Preview, si la categoría configurada aún no tiene un conductor
        // del tipo exacto, mostramos conductores online cercanos como fallback
        // para poder validar el flujo completo. Producción sigue filtrando por
        // el tipo de vehículo configurado para el servicio.
        if (nearbyDrivers.isEmpty &&
            widget.service.runtimeChannel == 'preview' &&
            requestedVehicleType != null) {
          final fallbackDrivers =
              await widget.service.nearbyOnlineDriverMarkers(
            latitude: markerLat,
            longitude: markerLng,
            radiusKm:
                asDouble(runtimeSettings['max_driver_request_radius_km']) ?? 10,
            vehicleType: null,
          );
          if (fallbackDrivers.isNotEmpty) {
            nearbyDrivers = fallbackDrivers;
            nearbyDriversLastNonEmptyAt = DateTime.now();
            nearbyDriversLastRequestedType = null;
          }
        }
      } catch (_) {
        // Si la consulta falla conservamos temporalmente la última lista válida
        // compatible con el servicio actual. Así evitamos el efecto
        // aparecer/desaparecer por problemas de red o una respuesta intermedia.
        nearbyDrivers =
            _compatibleCachedNearbyDrivers(requestedVehicleType);
      }
    }

    final next = _PassengerStateData(
      service: widget.service,
      openRide: openRide,
      activeTrip: activeTrip,
      activeDelivery: activeDelivery,
      offers: activeOffers,
      saved: listOfMaps(state['saved']),
      counterpart: mapOrNull(state['counterpart']),
      driverProfile: driverProfile,
      driverVehicle: driverVehicle,
      pendingRating: pendingRating,
      viewedCount: viewedCount,
      viewers: viewers,
      nearbyDrivers: nearbyDrivers,
    );

    if (revision != loadRevision) return next;

    if (!_samePassengerOfferList(
      cachedData?.offers ?? const <Map<String, dynamic>>[],
      activeOffers,
    )) {
      passengerOfferStateRevision++;
    }
    cachedData = next;
    passengerOfferPresentationActive = activeOffers.isNotEmpty;
    _syncPassengerOfferRealtime(next);
    _syncPassengerDriverLocationRealtime(next);
    _refreshPassengerPendingRating(revision);

    if (rideCancellationConfirmed) cancellingRideId = null;
    if (tripCancellationConfirmed) cancellingTripId = null;
    if (deliveryCancellationConfirmed) cancellingDeliveryId = null;

    _tryAutoAcceptOffers(
      activeOffers,
      openRide,
    );

    _maybePromptSearchRenewal(next);

    return next;
  }

  Future<void> _expirePassengerOffer(Map<String, dynamic> offer) async {
    final id = offer['id']?.toString();
    if (id == null || id.isEmpty) return;

    final expiredKey = _passengerOfferPresentationKey(offer);
    locallyExpiredPassengerOfferKeys.add(expiredKey);
    passengerOfferOverlayOffers = passengerOfferOverlayOffers
        .where(
          (row) => _passengerOfferPresentationKey(row) != expiredKey,
        )
        .toList();

    final currentData = cachedData;
    if (currentData != null) {
      final remainingOffers = currentData.offers
          .where((row) => _passengerOfferPresentationKey(row) != expiredKey)
          .toList();

      if (remainingOffers.length != currentData.offers.length) {
        loadRevision++;
        passengerOfferStateRevision++;
        cachedData = _PassengerStateData(
          service: currentData.service,
          openRide: currentData.openRide,
          activeTrip: currentData.activeTrip,
          activeDelivery: currentData.activeDelivery,
          offers: remainingOffers,
          saved: currentData.saved,
          counterpart: currentData.counterpart,
          driverProfile: currentData.driverProfile,
          driverVehicle: currentData.driverVehicle,
          pendingRating: currentData.pendingRating,
          viewedCount: currentData.viewedCount,
          viewers: currentData.viewers,
          nearbyDrivers: currentData.nearbyDrivers,
        );

        if (mounted) {
          setState(() {
            if (remainingOffers.isEmpty) {
              passengerOfferOverlayRide = null;
              passengerOfferPresentationActive = false;
              passengerOfferPresentationEpoch++;
              panelRevision++;
            }
            homeFuture = Future.value(cachedData!);
          });
          if (remainingOffers.isEmpty) {
            // Evita que un refresco pendiente vuelva a montar por un instante
            // la capa de ofertas antes de confirmar el cambio en el backend.
            passengerOfferRealtimeDebounce?.cancel();
            passengerOfferRealtimeDebounce = null;
            _settlePassengerSearchSheetImmediately();
          }
        }
      }
    }

    try {
      await widget.service.declineRideOffer(id);
    } catch (_) {}

    if (mounted) _refreshHome();
  }

  // Pasajero: la sugerencia aparece una sola vez por viaje, cuando el conductor
  // acepta. Reabrir la app no la repite.
  void _maybePromptOverlayOnTripStart(_PassengerStateData data) {
    final tripId = data.activeTrip?['id']?.toString();
    if (tripId == null || tripId.isEmpty || tripId == overlayPromptTripId) return;
    overlayPromptTripId = tripId;
    unawaited(_promptOverlayForTrip(tripId));
  }

  Future<void> _promptOverlayForTrip(String tripId) async {
    final isNew = await claimTripOverlayPrompt(tripId);
    if (!isNew || !mounted) return;
    await promptOverlayIfNeeded(context, widget.service);
  }

  void _maybePromptSearchRenewal(_PassengerStateData data) {
    final ride = data.openRide;
    if (ride == null ||
        data.activeTrip != null ||
        _isScheduledLater(ride) ||
        renewalDecisionOpen) {
      return;
    }

    final id = ride['id']?.toString();
    final expiresAt =
        DateTime.tryParse(ride['expires_at']?.toString() ?? '')?.toUtc();
    if (id == null ||
        id.isEmpty ||
        expiresAt == null ||
        expiresAt.isAfter(DateTime.now().toUtc())) {
      return;
    }

    // La clave incluye el vencimiento: cada ventana se pregunta una sola vez,
    // pero tras renovar (nuevo expires_at) puede volver a preguntarse. Datos
    // todavía viejos tras renovar no reabren el aviso ni cancelan la búsqueda.
    final promptKey = '$id|${expiresAt.toIso8601String()}';
    if (renewalPromptedRideIds.contains(promptKey)) {
      return;
    }

    renewalPromptedRideIds.add(promptKey);
    renewalDecisionOpen = true;
    renewalDecisionRideId = id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_showSearchRenewalDecision(ride));
    });
  }

  Future<void> _showSearchRenewalDecision(
    Map<String, dynamic> ride,
  ) async {
    final id = ride['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SearchRoundDecisionDialog(
        currentFare: asDouble(ride['proposed_fare']) ?? fare.toDouble(),
        currency: ride['currency']?.toString() ?? activeZone?['currency_code']?.toString() ?? 'BOB',
        isParcel: ride['service_mode'] == 'parcel',
      ),
    );

    if (!mounted) return;
    renewalDecisionOpen = false;
    renewalDecisionRideId = null;

    if (result == 'continue') {
      try {
        await _searchAgainFor(
          ride,
          fare: asDouble(ride['proposed_fare']) ?? fare.toDouble(),
        );
        if (mounted) _refreshHome();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo continuar la búsqueda: $e')),
        );
        return _reopenSearchRenewalDecision(ride);
      }
      return;
    }

    if (result == 'raise') {
      final newFare = await _askSearchFare(
        asDouble(ride['proposed_fare']) ?? fare.toDouble(),
        ride['currency']?.toString() ??
            activeZone?['currency_code']?.toString() ??
            'BOB',
        id,
      );
      if (!mounted) return;
      // "Volver" y los errores regresan a la decisión: nunca cancelan la búsqueda.
      if (newFare == null) {
        return _reopenSearchRenewalDecision(ride);
      }
      try {
        await _searchAgainFor(ride, fare: newFare);
        setState(() {
          fare = newFare;
          fareManuallyEdited = true;
        });
        _refreshHome();
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar la oferta: $e')),
        );
        return _reopenSearchRenewalDecision(ride);
      }
    }

    await _cancelExpiredRideSilently(id);
  }

  /// Vuelve a buscar con la misma ruta, pago y servicio. El conductor solo ve
  /// solicitudes creadas hace menos de 3 min y renovar una fila vencida no la
  /// hace reaparecer; una solicitud nueva sí aparece y notifica. Los envíos
  /// conservan la renovación.
  Future<void> _searchAgainFor(
    Map<String, dynamic> ride, {
    required num fare,
  }) async {
    if (ride['service_mode'] == 'parcel') {
      await widget.service.renewRideRequest(
        ride['id']?.toString() ?? '',
        proposedFare: fare,
      );
      return;
    }
    await widget.service.createRideRequest(
      category: ride['category']?.toString() ?? 'economy',
      pickupAddress: ride['pickup_address']?.toString() ?? '',
      destinationAddress: ride['destination_address']?.toString() ?? '',
      proposedFare: fare,
      paymentMethod: ride['payment_method']?.toString() ?? 'cash',
      pickupLatitude: asDouble(ride['pickup_latitude']),
      pickupLongitude: asDouble(ride['pickup_longitude']),
      destinationLatitude: asDouble(ride['destination_latitude']),
      destinationLongitude: asDouble(ride['destination_longitude']),
      routeDistanceKm: asDouble(ride['route_distance_km']),
      routeDurationMinutes: (ride['route_duration_minutes'] as num?)?.toInt(),
    );
  }

  Future<void> _reopenSearchRenewalDecision(Map<String, dynamic> ride) {
    final id = ride['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return Future.value();
    renewalDecisionOpen = true;
    renewalDecisionRideId = id;
    return _showSearchRenewalDecision(ride);
  }

  // El controlador vive en _SearchFareDialogState: liberarlo aquí, tras el
  // await, lo destruía mientras la ruta del diálogo aún se animaba al cerrar.
  // La regla (moneda y paso) viene del servidor cuando está disponible; si no,
  // el panel usa el respaldo local por moneda.
  Future<num?> _askSearchFare(
    num currentFare,
    String currency,
    String rideId,
  ) async {
    final rule = await widget.service.passengerSearchFareRule(rideId);
    if (!mounted) return null;
    final ruleCurrency = rule?['currency']?.toString() ?? currency;
    final ruleStep =
        asDouble(rule?['step']) ?? expressSearchFareStep(ruleCurrency);
    return showDialog<num>(
      context: context,
      builder: (_) => _SearchFareDialog(
        initialFare: currentFare,
        currency: ruleCurrency,
        step: ruleStep,
      ),
    );
  }

  Future<void> _cancelExpiredRideSilently(String rideId) async {
    locallyCancelledRideIds.add(rideId);
    try {
      await widget.service.cancelRideRequest(
        rideId,
        reason: 'Tiempo de búsqueda vencido',
      );
    } catch (_) {}
    if (!mounted) return;
    widget.onHardReset();
  }

  void _setAutoAcceptNearest(bool value) {
    setState(() => autoAcceptNearest = value);
    final data = cachedData;

    if (value && data != null) {
      _tryAutoAcceptOffers(data.offers, data.openRide);
    }
  }

  void _tryAutoAcceptOffers(
    List<Map<String, dynamic>> offers,
    Map<String, dynamic>? openRide,
  ) {
    if (!autoAcceptNearest ||
        autoAccepting ||
        openRide == null ||
        offers.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    final valid = offers.where((offer) {
      if (offer['status']?.toString() != 'pending') return false;
      final expiresAt =
          DateTime.tryParse(offer['expires_at']?.toString() ?? '')?.toUtc();
      return expiresAt == null || expiresAt.isAfter(now);
    }).toList();

    if (valid.isEmpty) return;

    final requestedFare = asDouble(openRide['proposed_fare']);
    valid.sort((a, b) {
      final aFare = asDouble(a['proposed_fare']) ?? 999999;
      final bFare = asDouble(b['proposed_fare']) ?? 999999;

      if (requestedFare != null) {
        final aMatches = aFare <= requestedFare + .001;
        final bMatches = bFare <= requestedFare + .001;
        if (aMatches != bMatches) return aMatches ? -1 : 1;
      }

      final aEta = (a['eta_minutes'] as num?)?.toInt() ?? 999;
      final bEta = (b['eta_minutes'] as num?)?.toInt() ?? 999;
      final etaCompare = aEta.compareTo(bEta);
      if (etaCompare != 0) return etaCompare;
      return aFare.compareTo(bFare);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || autoAccepting || !autoAcceptNearest) return;
      setState(() => autoAccepting = true);
      try {
        await _selectOffer(valid.first);
      } finally {
        if (mounted) setState(() => autoAccepting = false);
      }
    });
  }

  Future<void> _addParcelPhotos() async {
    if (parcelPhotosUploading || parcelPhotoPaths.length >= 4) return;
    // The package photo is captured by the rear camera, not the gallery.
    try {
      final photo = await parcelImagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 80,
        maxWidth: 1920,
      );
      if (photo == null || !mounted) return;
      setState(() => parcelPhotosUploading = true);

      final bytes = await photo.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw StateError('Cada foto debe ser menor a 5 MB');
      }
      final name = photo.name.toLowerCase();
      final extension = name.endsWith('.png') ? 'png' :
          name.endsWith('.webp') ? 'webp' : 'jpg';
      final mime = extension == 'png' ? 'image/png' :
          extension == 'webp' ? 'image/webp' : 'image/jpeg';
      final path = widget.service.userId + '/parcel/' +
          DateTime.now().microsecondsSinceEpoch.toString() +
          '-' + parcelPhotoPaths.length.toString() + '.' + extension;
      await supabase.storage.from('parcel-evidence').uploadBinary(
        path, bytes, fileOptions: FileOptions(
          upsert: false, contentType: mime));
      if (!mounted) return;
      setState(() => parcelPhotoPaths.add(path));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo tomar o guardar la foto: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => parcelPhotosUploading = false);
    }
  }

  bool _createServiceInFlight = false;

  Future<void> _createService() async {
    // Evita dos solicitudes de viaje o envío por doble toque mientras se
    // recalcula la ruta y se publica la primera solicitud.
    if (_createServiceInFlight) return;
    _createServiceInFlight = true;
    try {
      await _createServiceBody();
    } finally {
      _createServiceInFlight = false;
    }
  }

  Future<void> _createServiceBody() async {
    if (_expressOfflineBlocked(context)) return;
    if (serviceType == 'delivery' && (!parcelAvailable ||
        parcelSenderName.text.trim().isEmpty ||
        parcelSenderPhone.text.trim().isEmpty ||
        parcelRecipientName.text.trim().isEmpty ||
        parcelRecipientPhone.text.trim().isEmpty ||
        parcelPhotosUploading)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Completa remitente y destinatario para el envío.')));
      return;
    }
    final originalPickup = pickup;
    final to = destination;
    // If the first quote is still loading (or failed), never submit the
    // original default Bs 5 against a Chilean pickup.
    if (quoting || !passengerRideFareIsReady(fareQuote)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Espera una tarifa válida de tu zona antes de confirmar el viaje.',
        )),
      );
      if (!quoting) unawaited(_refreshFareQuote());
      return;
    }
    if (originalPickup == null || to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona origen y destino.')),
      );
      return;
    }

    final confirmedPickup = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => PickupConfirmationPage(initial: originalPickup),
      ),
    );
    if (confirmedPickup == null || !mounted) return;

    final from = confirmedPickup;
    await _loadRideServices(
      latitude: from.latitude,
      longitude: from.longitude,
    );
    if (!mounted) return;

    if (zoneOutsideCoverage || rideServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este punto de origen está fuera de una zona activa de Express.',
          ),
        ),
      );
      return;
    }

    final categoryStillAvailable = rideServices.any(
      (service) => service['service_key']?.toString() == category,
    );
    if (!categoryStillAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El servicio seleccionado no está disponible en esta zona. Elige uno de los servicios disponibles.',
          ),
        ),
      );
      return;
    }

    setState(() {
      pickup = from;
      creating = true;
    });

    // Al volver de confirmar la recogida no regresamos visualmente al selector
    // de categoría. La UI entra de inmediato en "Buscando conductores" mientras
    // recalculamos la ruta y publicamos la solicitud, evitando dobles toques.
    _movePassengerSheet(.36);

    try {
      // _fitRoute() ya actualiza la cotización cuando routeConfirmed=true.
      // Antes volvíamos a pedir _refreshFareQuote() aquí y duplicábamos la espera.
      await _fitRoute();
      if (!mounted) return;
      // Pickup confirmation can change the route, zone and currency.
      // Use only the just-verified quote; a temporary network failure must
      // not let an outdated BOB/CLP amount reach createRideRequest.
      if (!passengerRideFareIsReady(fareQuote)) {
        _movePassengerSheet(_rideChooserSheetFraction(context));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'No se pudo actualizar la tarifa del origen. Reintenta el precio.',
          )),
        );
        return;
      }

      final distanceMeters = const Distance().as(
        LengthUnit.Meter,
        LatLng(from.latitude, from.longitude),
        LatLng(to.latitude, to.longitude),
      );
      if (distanceMeters < 25) {
        setState(() {
          destination = null;
          routeConfirmed = false;
          routeDistanceKm = null;
          routeDurationMinutes = null;
          roadRoute = const [];
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_pickDestination());
        });
        return;
      }

      final resolvedAddresses = await Future.wait<String>([
        () async {
          if (!_isExpressPlaceholderAddress(from.label)) {
            return from.label.trim();
          }
          final resolved = await _expressReverseGeocodeAddress(
            LatLng(from.latitude, from.longitude),
          );
          return resolved ?? '';
        }(),
        () async {
          if (!_isExpressPlaceholderAddress(to.label)) {
            return to.label.trim();
          }
          final resolved = await _expressReverseGeocodeAddress(
            LatLng(to.latitude, to.longitude),
          );
          return resolved ?? '';
        }(),
      ]);
      if (!mounted) return;
      final resolvedPickupAddress = resolvedAddresses[0];
      final resolvedDestinationAddress = resolvedAddresses[1];
      // No descartes ni reinicies el punto cuando una búsqueda previa no
      // resolvió el texto. createRideRequest vuelve a resolver las coordenadas
      // con Photon y Nominatim antes de guardar la operación.

      // Carga central solo durante la publicación; al confirmar el servidor se
      // retira y la pantalla normal de búsqueda toma el control.
      final createdRide = await runExpressPublishing<Map<String, dynamic>>(
        context,
        () => widget.service.createRideRequest(
          category: category,
          serviceMode: serviceType == 'delivery' ? 'parcel' : 'taxi',
          parcelKind: serviceType == 'delivery' ? parcelKind : null,
          senderName: serviceType == 'delivery' ? parcelSenderName.text : null,
          senderPhone: serviceType == 'delivery' ? parcelSenderPhone.text : null,
          recipientName: serviceType == 'delivery' ? parcelRecipientName.text : null,
          recipientPhone: serviceType == 'delivery' ? parcelRecipientPhone.text : null,
          packageDetails: serviceType == 'delivery'
              ? parcelDescription.text : null,
          parcelPhotos: serviceType == 'delivery'
              ? List<String>.from(parcelPhotoPaths) : const [],
          pickupAddress: resolvedPickupAddress,
          destinationAddress: resolvedDestinationAddress,
          proposedFare: fare,
          paymentMethod: payment,
          pickupLatitude: from.latitude,
          pickupLongitude: from.longitude,
          destinationLatitude: to.latitude,
          destinationLongitude: to.longitude,
          routeDistanceKm: routeDistanceKm,
          routeDurationMinutes: routeDurationMinutes,
          scheduledFor: scheduledFor,
          baseFare: fareQuote['base_amount'] as num?,
          demandMultiplier: fareQuote['demand_multiplier'] as num?,
          demandLevel: fareQuote['demand_level']?.toString(),
          demandRequests: (fareQuote['demand_requests'] as num?)?.toInt(),
          demandDrivers: (fareQuote['demand_drivers'] as num?)?.toInt(),
          demandSectorKey: fareQuote['demand_sector_key']?.toString(),
        ),
      );

      if (!mounted) return;

      final previous = cachedData;
      final optimistic = _PassengerStateData(
        service: widget.service,
        openRide: createdRide,
        saved: previous?.saved ?? const [],
        counterpart: previous?.counterpart,
        driverProfile: previous?.driverProfile,
        pendingRating: previous?.pendingRating,
        nearbyDrivers: previous?.nearbyDrivers ?? const [],
      );

      setState(() {
        loadRevision++;
        panelRevision++;
        passengerOfferOverlayRideId = createdRide['id']?.toString();
        passengerOfferOverlayRide = null;
        passengerOfferOverlayOffers = <Map<String, dynamic>>[];
        passengerOfferPresentationActive = false;
        passengerOfferPresentationEpoch++;
        cachedData = optimistic;
        homeFuture = Future.value(optimistic);
        destination = null;
        routeConfirmed = false;
        scheduledFor = null;
        routeDistanceKm = null;
        routeDurationMinutes = null;
        roadRoute = const [];
        fareManuallyEdited = false;
        parcelPhotoPaths.clear();
        parcelSenderName.clear();
        parcelSenderPhone.clear();
        parcelRecipientName.clear();
        parcelRecipientPhone.clear();
        parcelDescription.clear();
        parcelKind = null;
      });

      mapController.move(
        LatLng(from.latitude, from.longitude),
        14.2,
      );
      _movePassengerSheet(.36);

      // La escucha debe arrancar en el mismo instante en que nace la solicitud.
      // Antes esperaba a que terminara _load(), y si una consulta secundaria
      // demoraba, la primera oferta quedaba invisible hasta recargar/tocar push.
      _syncPassengerOfferRealtime(optimistic);

      widget.onChanged();
      _refreshHome();
    } catch (e) {
      if (!mounted) return;
      final debtAction = await showCancellationDebtBlock(
        context,
        e,
        driver: false,
      );
      if (debtAction != null) {
        if (debtAction) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ExpressWalletPage(
                service: widget.service,
                driver: false,
              ),
            ),
          );
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo solicitar el viaje. Inténtalo nuevamente.'),
        ),
      );
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> _selectOffer(Map<String, dynamic> offer) async {
    if (_expressOfflineBlocked(context)) return;
    if (passengerOfferActionBusy) return;
    setState(() => passengerOfferActionBusy = true);
    stopExpressAlertSound();
    try {
      final selectedTripId = await runExpressStateTransition<String>(
        context,
        processingTitle: 'Confirmando conductor…',
        processingSubtitle: 'Estamos reservando esta oferta para ti.',
        successTitle: 'Conductor confirmado',
        successSubtitle: 'Ya puedes seguir su llegada desde el mapa.',
        eventName: 'OFFER_SELECTED',
        action: () => widget.service.selectRideOffer(offer['id'].toString()),
      );
      lastAnimatedPassengerTripId = selectedTripId;
      lastAnimatedPassengerTripStatus = 'driver_assigned';
      if (!mounted) return;
      setState(() {
        passengerOfferPresentationActive = false;
        passengerOfferPresentationEpoch++;
        panelRevision++;
        passengerOfferOverlayRide = null;
        passengerOfferOverlayOffers = <Map<String, dynamic>>[];
        final current = cachedData;
        if (current != null) {
          cachedData = _PassengerStateData(
            service: current.service,
            openRide: current.openRide,
            activeTrip: current.activeTrip,
            activeDelivery: current.activeDelivery,
            offers: const [],
            saved: current.saved,
            counterpart: current.counterpart,
            driverProfile: current.driverProfile,
            driverVehicle: current.driverVehicle,
            pendingRating: current.pendingRating,
            viewedCount: current.viewedCount,
            viewers: current.viewers,
            nearbyDrivers: current.nearbyDrivers,
          );
          homeFuture = Future.value(cachedData!);
        }
      });
      _refreshHome();
      widget.onChanged();
    } catch (e, stack) {
      if (!mounted) return;
      unawaited(AppErrorReporter.capture(e, stack,
          source: 'offer_accept', screen: 'driver_offer', eventName: 'OFFER_ACCEPT_FAILED'));
      final debtAction = await showCancellationDebtBlock(
        context,
        e,
        driver: false,
      );
      if (debtAction != null) {
        if (debtAction) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ExpressWalletPage(
                service: widget.service,
                driver: false,
              ),
            ),
          );
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyRideOfferError(e))),
      );
      _refreshHome();
    } finally {
      if (mounted) setState(() => passengerOfferActionBusy = false);
    }
  }

  Future<void> _declineOffer(Map<String, dynamic> offer) async {
    if (passengerOfferActionBusy) return;
    setState(() => passengerOfferActionBusy = true);
    stopExpressAlertSound();
    try {
      await widget.service.declineRideOffer(offer['id'].toString());
      if (!mounted) return;
      setState(() {
        passengerOfferOverlayOffers = passengerOfferOverlayOffers
            .where((row) => row['id']?.toString() != offer['id']?.toString())
            .toList();
        if (passengerOfferOverlayOffers.isEmpty) {
          passengerOfferOverlayRide = null;
          passengerOfferPresentationActive = false;
          passengerOfferPresentationEpoch++;
          panelRevision++;
        }
      });
      _refreshHome();
    } catch (_) {
      if (!mounted) return;
      _refreshHome();
    } finally {
      if (mounted) setState(() => passengerOfferActionBusy = false);
    }
  }

  void _showCancellingMessage(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('Cancelando $label…'),
            ],
          ),
        ),
      );
  }

  void _showCancelledMessage(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$label cancelado correctamente.')),
      );
  }

  Future<bool> _rideStillOpen(String rideId) async {
    try {
      final state = await widget.service
          .passengerHomeState()
          .timeout(const Duration(seconds: 6));

      final rawRide = state['open_ride'];
      if (rawRide is Map && rawRide['id']?.toString() == rideId) {
        return true;
      }

      final rawTrip = state['active_trip'];
      if (rawTrip is Map) {
        final linkedRideId = rawTrip['ride_request_id']?.toString() ??
            (rawTrip['ride_requests'] is Map
                ? (rawTrip['ride_requests'] as Map)['id']?.toString()
                : null);
        if (linkedRideId == rideId) return true;
      }

      return false;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _tripStillActive(String tripId) async {
    try {
      final state = await widget.service
          .passengerHomeState()
          .timeout(const Duration(seconds: 6));
      final raw = state['active_trip'];
      return raw is Map && raw['id']?.toString() == tripId;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _deliveryStillActive(String deliveryId) async {
    try {
      final state = await widget.service
          .passengerHomeState()
          .timeout(const Duration(seconds: 6));
      final raw = state['active_delivery'];
      return raw is Map && raw['id']?.toString() == deliveryId;
    } catch (_) {
      return true;
    }
  }

  Future<void> _cancelOpenRide(Map<String, dynamic> ride) async {
    final reason = await askExpressCancellationReason(context, 'solicitud');
    if (reason == null || !mounted) return;

    final rideId = ride['id'].toString();
    final confirmedFee = await confirmRideRequestCancellationFee(
      context,
      widget.service,
      rideId,
    );
    if (confirmedFee == null || !mounted) return;
    final previous = cachedData;

    setState(() {
      loadRevision++;
      panelRevision++;
      cancellingRideId = rideId;
      locallyCancelledRideIds.add(rideId);
      if (previous != null) {
        cachedData = _PassengerStateData(
          service: previous.service,
          activeTrip: previous.activeTrip,
          activeDelivery: previous.activeDelivery,
          saved: previous.saved,
          counterpart: previous.counterpart,
          driverProfile: previous.driverProfile,
          pendingRating: previous.pendingRating,
          nearbyDrivers: previous.nearbyDrivers,
        );
        homeFuture = Future.value(cachedData!);
      }
      routeConfirmed = false;
      destination = null;
      routeDistanceKm = null;
      routeDurationMinutes = null;
      roadRoute = const [];
    });
    _movePassengerSheet(.50);
    _showCancellingMessage('la solicitud');

    try {
      await widget.service
          .cancelRideRequest(
            rideId,
            reason: reason,
            confirmedFee: confirmedFee,
          )
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      _showCancelledMessage('Viaje');
      widget.onHardReset();
    } catch (_) {
      if (!mounted) return;

      final stillOpen = await _rideStillOpen(rideId);
      if (!mounted) return;

      if (!stillOpen) {
        _showCancelledMessage('Viaje');
        widget.onHardReset();
        return;
      }

      setState(() {
        cancellingRideId = null;
        locallyCancelledRideIds.remove(rideId);
        if (previous != null) {
          cachedData = previous;
          homeFuture = Future.value(previous);
        }
      });
      _refreshHome();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo confirmar la cancelación. Inténtalo nuevamente.',
            ),
          ),
        );
    }
  }

  Future<void> _cancelActiveTrip(Map<String, dynamic> trip) async {
    final reason = await askExpressCancellationReason(context, 'viaje');
    if (reason == null || !mounted) return;

    final tripId = trip['id'].toString();
    final confirmedFee = await confirmTripCancellationFee(
      context,
      widget.service,
      tripId,
    );
    if (confirmedFee == null || !mounted) return;
    final previous = cachedData;

    setState(() {
      loadRevision++;
      panelRevision++;
      cancellingTripId = tripId;
      locallyCancelledTripIds.add(tripId);
      if (previous != null) {
        cachedData = _PassengerStateData(
          service: previous.service,
          openRide: previous.openRide,
          activeDelivery: previous.activeDelivery,
          offers: previous.offers,
          saved: previous.saved,
          counterpart: previous.counterpart,
          driverProfile: previous.driverProfile,
          pendingRating: previous.pendingRating,
          viewedCount: previous.viewedCount,
          viewers: previous.viewers,
          nearbyDrivers: previous.nearbyDrivers,
        );
        homeFuture = Future.value(cachedData!);
      }
    });
    _showCancellingMessage('el viaje');

    try {
      await widget.service
          .cancelTrip(
            tripId,
            reason: reason,
            confirmedFee: confirmedFee,
          )
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      _showCancelledMessage('Viaje');
      widget.onHardReset();
    } catch (_) {
      if (!mounted) return;

      final stillActive = await _tripStillActive(tripId);
      if (!mounted) return;

      if (!stillActive) {
        _showCancelledMessage('Viaje');
        widget.onHardReset();
        return;
      }

      setState(() {
        cancellingTripId = null;
        locallyCancelledTripIds.remove(tripId);
        if (previous != null) {
          cachedData = previous;
          homeFuture = Future.value(previous);
        }
      });
      _refreshHome();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo cancelar el viaje. Inténtalo nuevamente.',
            ),
          ),
        );
    }
  }

  Future<void> _cancelActiveDelivery(Map<String, dynamic> delivery) async {
    final reason = await askExpressCancellationReason(context, 'delivery');
    if (reason == null || !mounted) return;

    final deliveryId = delivery['id'].toString();
    final previous = cachedData;

    setState(() {
      loadRevision++;
      panelRevision++;
      cancellingDeliveryId = deliveryId;
      locallyCancelledDeliveryIds.add(deliveryId);
      if (previous != null) {
        cachedData = _PassengerStateData(
          service: previous.service,
          openRide: previous.openRide,
          activeTrip: previous.activeTrip,
          offers: previous.offers,
          saved: previous.saved,
          counterpart: previous.counterpart,
          driverProfile: previous.driverProfile,
          pendingRating: previous.pendingRating,
          viewedCount: previous.viewedCount,
          viewers: previous.viewers,
          nearbyDrivers: previous.nearbyDrivers,
        );
        homeFuture = Future.value(cachedData!);
      }
    });
    _showCancellingMessage('el delivery');

    try {
      await widget.service
          .cancelDelivery(deliveryId, reason: reason)
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      _showCancelledMessage('Delivery');
      widget.onHardReset();
    } catch (_) {
      if (!mounted) return;

      final stillActive = await _deliveryStillActive(deliveryId);
      if (!mounted) return;

      if (!stillActive) {
        _showCancelledMessage('Delivery');
        widget.onHardReset();
        return;
      }

      setState(() {
        cancellingDeliveryId = null;
        locallyCancelledDeliveryIds.remove(deliveryId);
        if (previous != null) {
          cachedData = previous;
          homeFuture = Future.value(previous);
        }
      });
      _refreshHome();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo cancelar el delivery. Inténtalo nuevamente.',
            ),
          ),
        );
    }
  }

  Future<void> _openPassengerTripInWaze(Map<String, dynamic> trip) async {
    final rawRide = trip['ride_requests'];
    final ride = rawRide is Map
        ? Map<String, dynamic>.from(rawRide)
        : <String, dynamic>{};
    final status = trip['status']?.toString() ?? 'driver_assigned';
    final beforePickup = const {
      'driver_assigned',
      'driver_arriving',
      'driver_waiting',
      'passenger_on_way',
    }.contains(status);
    final latitude = asDouble(
      ride[beforePickup ? 'pickup_latitude' : 'destination_latitude'],
    );
    final longitude = asDouble(
      ride[beforePickup ? 'pickup_longitude' : 'destination_longitude'],
    );
    if (latitude == null || longitude == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este viaje todavía no tiene coordenadas para abrir Waze.'),
        ),
      );
      return;
    }

    final latLng = '$latitude,$longitude';
    final appUri = Uri.parse('waze://?ll=$latLng&navigate=yes');
    final webUri = Uri.https(
      'waze.com',
      '/ul',
      {'ll': latLng, 'navigate': 'yes'},
    );
    try {
      if (await canLaunchUrl(appUri)) {
        final opened = await launchUrl(
          appUri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) return;
      }
      final opened = await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir Waze.')),
    );
  }

  void _openDeliveryTracking(Map<String, dynamic> delivery) {
    final driverId = delivery['courier_id']?.toString();
    if (driverId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceTrackingPage(
          title: 'Seguimiento del delivery',
          status: delivery['status']?.toString() ?? '',
          driverId: driverId,
          pickupLatitude: asDouble(delivery['pickup_latitude']),
          pickupLongitude: asDouble(delivery['pickup_longitude']),
          destinationLatitude: asDouble(delivery['dropoff_latitude']),
          destinationLongitude: asDouble(delivery['dropoff_longitude']),
        ),
      ),
    );
  }

  void _showPassengerMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: ExpressOfficialLogo(size: 48, radius: 15),
                title: Text(
                  'Express',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('Viajes'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Mis servicios'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onHistory();
                },
              ),
              if (runtimeSettings['scheduled_rides_enabled'] != false)
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Viajes programados'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.onScheduledTrips();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Pagos y movimientos'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onPayments();
                },
              ),
              ListTile(
                leading: const Icon(Icons.card_giftcard_outlined),
                title: const Text('Cupones y beneficios'),
                subtitle: const Text('Fidelidad, promociones y referidos'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(context, MaterialPageRoute<void>(
                    builder: (_) => const BenefitsPage(),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: const Text('Lugares guardados'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onSavedPlaces();
                },
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Seguridad y SOS'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onSafety();
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_none_rounded),
                title: const Text('Centro Express'),
                subtitle: const Text('Avisos, chat y calificaciones'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ExpressCenterPage(service: widget.service),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Mi perfil'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onProfile();
                },
              ),
              if (overlayAllowed)
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: const Text('Llamadas'),
                  subtitle: const Text('Llamadas emergentes en cualquier momento'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CallPreferencesPage(service: widget.service),
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('Cambiar a modo Conductor'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onSwitchMode();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _onConnectivityChanged() {
    // Al recuperar la conexión se sincroniza una sola vez, sin duplicar lecturas.
    if (!mounted || !ExpressConnectivityMonitor.instance.isOnline) return;
    _refreshHome();
  }

  @override
  void dispose() {
    ExpressConnectivityMonitor.instance.removeListener(_onConnectivityChanged);
    if (renewalDecisionOpen && renewalDecisionRideId != null) {
      unawaited(
        widget.service.cancelRideRequest(
          renewalDecisionRideId!,
          reason: 'Sin respuesta al vencer la búsqueda',
        ),
      );
    }
    passengerMapPositionSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    searchRenewalWatch?.cancel();
    timer?.cancel();
    passengerOfferRealtimeDebounce?.cancel();
    zoneServiceCatalogDebounce?.cancel();
    passengerOfferBootstrapTimer?.cancel();
    passengerCriticalStateTimer?.cancel();
    passengerLiveOfferTimer?.cancel();
    zoneServiceCatalogChannel?.unsubscribe();
    passengerDriverLocationChannel?.unsubscribe();
    unawaited(passengerOfferRealtimeSubscription?.cancel());
    unawaited(passengerForegroundPushSubscription?.cancel());
    mapController.dispose();
    sheetController.dispose();
    for (final field in [
      parcelSenderName, parcelSenderPhone, parcelRecipientName,
      parcelRecipientPhone, parcelDescription,
    ]) { field.dispose(); }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ExpressConnectivityMonitor.instance.onAppResumed();
      ExpressCallPresence.start(widget.service);
      unawaited(syncDriverPushOverlayState(widget.service));
      unawaited(syncOverlayCallPreference(widget.service).then((granted) {
        if (mounted) setState(() => overlayAllowed = granted);
      }));
      unawaited(_refreshPassengerLiveOfferState());
      unawaited(_refreshPassengerCriticalState());
      _refreshHome();
    }

    if (state == AppLifecycleState.paused) {
      ExpressCallPresence.stop();
    }

    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.detached) &&
        renewalDecisionOpen &&
        renewalDecisionRideId != null) {
      final rideId = renewalDecisionRideId!;
      renewalDecisionOpen = false;
      renewalDecisionRideId = null;
      unawaited(
        widget.service.cancelRideRequest(
          rideId,
          reason: 'Sin respuesta al vencer la búsqueda',
        ),
      );
    }
  }

  Widget _buildPassengerBottomPanel(
    ScrollController? controller,
    _PassengerStateData data,
  ) {
    return _PassengerBottomPanel(

                      controller: controller,
                      data: data,
                    services: rideServices,
                    settings: runtimeSettings,
                    zoneName: activeZone?['name']?.toString(),
                    currencyCode: passengerRideCurrency(
                      fareQuote: fareQuote,
                      activeZone: activeZone,
                      routeConfirmed: routeConfirmed,
                    ),
                    serviceType: serviceType,
                    parcelAvailable: parcelAvailable,
                    parcelKind: parcelKind,
                    onParcelKind: (kind) => setState(() => parcelKind = kind),
                    parcelSenderName: parcelSenderName,
                    parcelSenderPhone: parcelSenderPhone,
                    parcelRecipientName: parcelRecipientName,
                    parcelRecipientPhone: parcelRecipientPhone,
                    parcelDescription: parcelDescription,
                    parcelPhotoCount: parcelPhotoPaths.length,
                    parcelPhotosUploading: parcelPhotosUploading,
                    onAddParcelPhotos: _addParcelPhotos,
                    category: category,
                    payment: payment,
                    fare: fare,
                    fareReady: passengerRideFareIsReady(fareQuote),
                    minimumFare:
                        asDouble(fareQuote['minimum_allowed_fare']) ??
                            asDouble(fareQuote['recommended_fare']) ??
                            fare.toDouble(),
                    fareIncrement:
                        asDouble(fareQuote['fare_rounding_increment']) ??
                            (passengerRideCurrency(
                              fareQuote: fareQuote,
                              activeZone: activeZone,
                              routeConfirmed: routeConfirmed,
                            ) == 'CLP' ? 1.0 : 0.01),
                    scheduledFor: scheduledFor,
                    pickup: pickup,
                    destination: destination,
                    routeDistanceKm: routeDistanceKm,
                    routeDurationMinutes: routeDurationMinutes,
                    routing: routing,
                    quoting: quoting,
                    creating: creating,
                    routeConfirmed: routeConfirmed,
                    autoAcceptNearest: autoAcceptNearest,
                    onAutoAcceptNearest: _setAutoAcceptNearest,
                    onType: (value) {
                      // No new page, pickup or route recalculation: Taxi and
                      // Envíos use the same route, fare and offer engine.
                      if (value == 'delivery' && !parcelAvailable) return;
                      setState(() {
                        serviceType = value;
                      });
                    },
                    onCategory: (value) {
                      if (category == value) return;
                      setState(() {
                        category = value;
                        fareManuallyEdited = false;
                        fareQuote = const <String, dynamic>{};
                        quoting = true;
                        ++fareQuoteEpoch;
                      });
                      _refreshHome();
                      unawaited(_refreshFareQuote());
                    },
                    onRetryFare: () => unawaited(_refreshFareQuote()),
                    onPayment: (value) => setState(() => payment = value),
                    onFare: (value) => setState(() {
                      final floor =
                          asDouble(fareQuote['minimum_allowed_fare']) ??
                              asDouble(fareQuote['recommended_fare']) ??
                              fare.toDouble();
                      fare = value.toDouble() < floor ? floor : value;
                      fareManuallyEdited = true;
                    }),
                    onSchedule: (value) =>
                        setState(() => scheduledFor = value),
                    onPickup: _pickPickup,
                    onDestination: _pickDestination,
                    onConfirmRoute: () {
                      _confirmRoute();
                    },
                    onReviewRoute: () {
                      setState(() {
                        routeConfirmed = false;
                        fareQuote = const <String, dynamic>{};
                        quoting = false;
                        ++fareQuoteEpoch;
                      });
                      final confirmFraction =
                          _routeConfirmationSheetFraction(context);
                      _movePassengerSheet(confirmFraction);
                      _fitRouteCamera(panelFraction: confirmFraction);
                    },
                    onCreate: _createService,
                    onOffer: _selectOffer,
                    onDeclineOffer: _declineOffer,
                    onExpireOffer: _expirePassengerOffer,
                    onCancelRide: _cancelOpenRide,
                    onCancelTrip: _cancelActiveTrip,
                    onCancelDelivery: _cancelActiveDelivery,
                    onTripTracking: _openPassengerTripInWaze,
                    onDeliveryTracking: _openDeliveryTracking,
                    onRatePending: _ratePending,
                    onHistory: widget.onHistory,
                    onSavedPlaces: widget.onSavedPlaces,
                    onSaved: (row) {
                      final lat = asDouble(row['latitude']);
                      final lng = asDouble(row['longitude']);
                      if (lat == null || lng == null) return;
                      setState(() {
                        passengerFlowMinimized = false;
                        destination = PickedLocation(
                          label: row['address']?.toString() ??
                              row['label']?.toString() ??
                              'Destino',
                          latitude: lat,
                          longitude: lng,
                        );
                        routeConfirmed = false;
                      });
                      final confirmFraction =
                          _routeConfirmationSheetFraction(context);
                      _movePassengerSheet(confirmFraction);
                      _fitRoute();
                    },
                  
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PassengerStateData>(
      future: homeFuture,
      builder: (context, snapshot) {
            final homePanelFraction = _passengerHomeSheetFraction(context);
        final rideChooserFraction =
            _rideChooserSheetFraction(context);

        // cachedData es la fuente visual de verdad. FutureBuilder conserva
        // temporalmente snapshot.data de la Future anterior al cambiar de
        // consulta; usar ese snapshot podía resucitar una solicitud que ya
        // había sido cancelada y mantener vivo el contador de búsqueda.
        final data = _visiblePassengerData(cachedData ?? snapshot.data);
        _observePassengerTripTransition(data);
        _observePassengerCompletion(data);
        // La tarjeta de calificación se muestra solo sin servicio activo: la
        // hoja de confirmación debe crecer con ella para no recortarla.
        final hasPendingRatingCard = data?.pendingRating != null &&
            data?.activeTrip == null &&
            data?.activeDelivery == null &&
            data?.openRide == null;
        final confirmRouteFraction = _routeConfirmationSheetFraction(
          context,
          hasPendingRating: hasPendingRatingCard,
        );
        final initialLoading = data == null;
        final nowUtc = DateTime.now().toUtc();

        final dataRideId = data?.openRide?['id']?.toString();
        final overlayRideMatches = passengerOfferOverlayRideId != null &&
            (passengerOfferOverlayRideId == dataRideId ||
                passengerOfferOverlayRide != null);
        final useOfferOverlay =
            overlayRideMatches && passengerOfferOverlayOffers.isNotEmpty;

        final Map<String, dynamic>? offerRide;
        final List<Map<String, dynamic>> offerSource;
        if (passengerLiveOfferStateReady) {
          offerRide = passengerLiveOfferRide;
          offerSource = passengerLiveOffers;
        } else if (useOfferOverlay) {
          offerRide = passengerOfferOverlayRide ?? data?.openRide;
          offerSource = passengerOfferOverlayOffers;
        } else {
          offerRide = data?.openRide;
          offerSource = data?.offers ?? const <Map<String, dynamic>>[];
        }

        final usingAuthoritativeLiveOffers =
            passengerLiveOfferStateReady &&
            identical(offerSource, passengerLiveOffers);

        final effectivePassengerOffers = offerSource.where((offer) {
          if (offer['status']?.toString() != 'pending') return false;

          // El feed vivo viene directamente del RPC autoritativo del servidor.
          // Una expiración local antigua nunca puede ocultar una oferta que
          // Supabase todavía devuelve como pendiente y vigente.
          if (!usingAuthoritativeLiveOffers &&
              locallyExpiredPassengerOfferKeys.contains(
                _passengerOfferPresentationKey(offer),
              )) {
            return false;
          }

          final expiresAt =
              DateTime.tryParse(offer['expires_at']?.toString() ?? '')?.toUtc();
          return expiresAt == null || expiresAt.isAfter(nowUtc);
        }).toList();

        final hasPassengerOffers = offerRide != null &&
            !_isScheduledLater(offerRide) &&
            effectivePassengerOffers.isNotEmpty;

        final compactSearching = data != null &&
            data.openRide != null &&
            !_isScheduledLater(data.openRide!) &&
            !hasPassengerOffers;
        final submittingRide = creating &&
            data?.openRide == null &&
            data?.activeTrip == null &&
            data?.activeDelivery == null;
        final hasActivePassengerService =
            data?.activeTrip != null || data?.activeDelivery != null;
        final activePassengerStatus =
            data?.activeTrip?['status']?.toString() ?? '';
        final passengerTripNavigationLocked =
            _passengerTripNavigationLocked(data?.activeTrip);
        final effectivePassengerFlowMinimized =
            passengerTripNavigationLocked ? false : passengerFlowMinimized;
        final rawPassengerFlowActive = destination != null ||
            submittingRide ||
            data?.openRide != null ||
            hasPassengerOffers ||
            hasActivePassengerService;
        final passengerFlowActive =
            rawPassengerFlowActive && !effectivePassengerFlowMinimized;
        _reportPassengerFlowState(passengerFlowActive);
        _reportPassengerTripNavigationLock(passengerTripNavigationLocked);
        if (passengerTripNavigationLocked && passengerFlowMinimized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && passengerFlowMinimized) {
              setState(() => passengerFlowMinimized = false);
            }
          });
        }

        final activePassengerPanelFraction = data?.activeDelivery != null
            ? .56
            : switch (activePassengerStatus) {
                'driver_assigned' || 'driver_arriving' => .62,
                'driver_waiting' || 'passenger_on_way' => .58,
                'in_progress' => .43,
                'emergency' => .48,
                _ => .52,
              };
        final passengerSetupFlow = destination != null &&
            data?.openRide == null &&
            data?.activeTrip == null &&
            data?.activeDelivery == null &&
            !creating;
        final minimizedFlowTitle = hasActivePassengerService
            ? 'Viaje activo'
            : data?.openRide != null
                ? 'Solicitud activa'
                : 'Preparando viaje';

        ExpressDiagnosticsHub.updatePassengerUi(
          openRideId: data?.openRide?['id']?.toString(),
          uiOfferCount: effectivePassengerOffers.length,
          searchPanelMounted: compactSearching,
          offersCardMounted: hasPassengerOffers,
          loadRevision: loadRevision,
          panelRevision: panelRevision,
        );

        if (passengerLiveOfferStateReady &&
            passengerLiveOffers.isNotEmpty &&
            !hasPassengerOffers) {
          unawaited(
            AppErrorReporter.warning(
              'El feed vivo tiene ofertas pero la tarjeta no está montada.',
              source: 'passenger_offer_ui',
              screen: 'passenger_home',
              eventName: 'LIVE_OFFERS_NOT_MOUNTED',
              context: {
                'live_offer_count': passengerLiveOffers.length,
                'effective_offer_count': effectivePassengerOffers.length,
                'live_ride_id': passengerLiveOfferRide?['id']?.toString(),
                'data_ride_id': data?.openRide?['id']?.toString(),
                'panel_revision': panelRevision,
                'load_revision': loadRevision,
              },
            ),
          );
        } else if (passengerLiveOffers.isNotEmpty && hasPassengerOffers) {
          unawaited(
            AppErrorReporter.event(
              'LIVE_OFFERS_CARD_MOUNTED',
              source: 'passenger_offer_ui',
              screen: 'passenger_home',
              context: {
                'offer_count': effectivePassengerOffers.length,
                'ride_id': offerRide['id']?.toString(),
              },
            ),
          );
        }

        final searchingNow = data != null &&
            data.openRide != null &&
            !_isScheduledLater(data.openRide!);
        final markers = <Marker>[];
        final lines = <Polyline>[];

        final activeTrip = data?.activeTrip;
        if (activeTrip != null) {
          final status = activeTrip['status']?.toString() ?? 'driver_assigned';
          final ride = activeTrip['ride_requests'] is Map
              ? Map<String, dynamic>.from(activeTrip['ride_requests'] as Map)
              : <String, dynamic>{};
          final driverLat = asDouble(data?.driverProfile?['latitude']);
          final driverLng = asDouble(data?.driverProfile?['longitude']);
          final driverPoint = driverLat != null && driverLng != null
              ? LatLng(driverLat, driverLng)
              : null;
          final pickupLat = asDouble(ride['pickup_latitude']);
          final pickupLng = asDouble(ride['pickup_longitude']);
          final pickupPoint = pickupLat != null && pickupLng != null
              ? LatLng(pickupLat, pickupLng)
              : null;
          final destinationLat = asDouble(ride['destination_latitude']);
          final destinationLng = asDouble(ride['destination_longitude']);
          final destinationPoint =
              destinationLat != null && destinationLng != null
                  ? LatLng(destinationLat, destinationLng)
                  : null;

          final beforePickup =
              status == 'driver_assigned' || status == 'driver_arriving';
          final inTrip = status == 'in_progress' || status == 'emergency';
          final target = beforePickup
              ? pickupPoint
              : inTrip
                  ? destinationPoint
                  : null;

          if (driverPoint != null) {
            markers.add(
              Marker(
                point: driverPoint,
                width: 52,
                height: 52,
                child: ExpressMapVehicleMarker(
                  key: ValueKey('passenger-driver-${activeTrip['id']}'),
                  vehicleType: expressMapVehicleType(
                    data?.driverVehicle?['vehicle_type'],
                    summary: data?.driverProfile?['vehicle_summary']?.toString(),
                  ),
                  position: driverPoint,
                  headingDegrees: asDouble(data?.driverProfile?['heading_degrees']),
                  navigating: inTrip,
                  scale: _expressMapMarkerScale(passengerMapZoom),
                ),
              ),
            );
          }
          if (target != null) {
            markers.add(
              Marker(
                point: target,
                width: 50,
                height: 50,
                // Mismo lenguaje visual que el conductor: A azul (recogida),
                // B verde (destino). Antes el destino era un pin oscuro.
                child: beforePickup
                    ? const _RoutePointMapPin(
                        label: 'A',
                        background: expressBlue,
                      )
                    : const _RoutePointMapPin(
                        label: 'B',
                        background: Color(0xFF12B76A),
                      ),
              ),
            );
          }
          if (driverPoint != null && target != null) {
            _refreshPassengerActiveRoadRoute(
              activeTrip['id'].toString(),
              status,
              driverPoint,
              target,
            );
            if (passengerActiveRoadRoute.length >= 2) {
              lines.add(
                Polyline(
                  points: passengerActiveRoadRoute,
                  strokeWidth: 5,
                  color: expressBlue,
                ),
              );
            }
            final stageKey = activeTrip['id'].toString() + ':' + status;
            _followPassengerActiveTrip(stageKey, driverPoint, target);
          }
        } else {
          passengerMapTripStageKey = null;
          passengerLastMapFollowPoint = null;
          passengerLastMapFollowAt = null;
          passengerActiveRoadRouteKey = null;
          passengerActiveRoadRoute = const [];

          if (data?.openRide != null &&
              !_isScheduledLater(data!.openRide!)) {
            final radarLat = asDouble(data.openRide!['pickup_latitude']);
            final radarLng = asDouble(data.openRide!['pickup_longitude']);
            if (radarLat != null && radarLng != null) {
              markers.add(
                Marker(
                  point: LatLng(radarLat, radarLng),
                  width: 250,
                  height: 250,
                  child: const IgnorePointer(child: _MapSearchRadar()),
                ),
              );
            }
          }

          if (pickup != null) {
            markers.add(
              Marker(
                point: LatLng(pickup!.latitude, pickup!.longitude),
                width: 50,
                height: 50,
                child: Transform.scale(
                  scale: _expressMapMarkerScale(passengerMapZoom),
                  child: const _MapPin(
                    icon: Icons.my_location_rounded,
                    dark: false,
                  ),
                ),
              ),
            );
          } else if (current != null) {
            markers.add(
              Marker(
                point: current!,
                width: 50,
                height: 50,
                child: Transform.scale(
                  scale: _expressMapMarkerScale(passengerMapZoom),
                  child: const _MapPin(
                    icon: Icons.person_rounded,
                    dark: false,
                  ),
                ),
              ),
            );
          }

          if (destination != null && !searchingNow) {
            markers.add(
              Marker(
                point: LatLng(
                  destination!.latitude,
                  destination!.longitude,
                ),
                width: 50,
                height: 50,
                // Destino con la misma B verde que usa el conductor.
                child: const _RoutePointMapPin(
                  label: 'B',
                  background: Color(0xFF12B76A),
                ),
              ),
            );
          }

          if (searchingNow && data.openRide != null) {
            final ride = data.openRide!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final lat = asDouble(ride['pickup_latitude']);
              final lng = asDouble(ride['pickup_longitude']);
              if (lat == null || lng == null) return;
              final camera = mapController.camera;
              final center = camera.center;
              final farFromPickup = const Distance().as(
                    LengthUnit.Meter,
                    center,
                    LatLng(lat, lng),
                  ) >
                  900;
              if (farFromPickup || camera.zoom < 13.8 || camera.zoom > 15.4) {
                _focusSearchCamera(ride);
              }
            });
          }

          if (data != null && data.nearbyDrivers.isNotEmpty) {
            for (final driver in data.nearbyDrivers) {
              final lat = asDouble(driver['latitude']);
              final lng = asDouble(driver['longitude']);
              if (lat == null || lng == null) continue;
              markers.add(
                Marker(
                  point: LatLng(lat, lng),
                  width: 48,
                  height: 56,
                  child: ExpressMapVehicleMarker(
                    vehicleType: expressMapVehicleType(driver['vehicle_type']),
                    scale: _expressMapMarkerScale(passengerMapZoom),
                    headingDegrees: asDouble(driver['heading_degrees']),
                  ),
                ),
              );
            }
          }

          if (pickup != null && destination != null && !searchingNow &&
              roadRoute.length >= 2) {
            lines.add(
              Polyline(
                points: roadRoute,
                strokeWidth: 5,
                color: expressBlue,
              ),
            );
          }
        }

        return Scaffold(
          body: Stack(
            children: [
              // Hijo no posicionado que ocupa todo el cuerpo: sin él, al llegar
              // ofertas (solo quedan Positioned) el Stack mide cero y la
              // pantalla del pasajero se vuelve blanca.
              const SizedBox.expand(),
              Positioned.fill(
                child: FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: pickup == null
                        ? current ?? expressFallback
                        : LatLng(pickup!.latitude, pickup!.longitude),
                    initialZoom: current == null && pickup == null ? 13 : 14.6,
                    // El selector de ubicaciones es otra pantalla.
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                    onPositionChanged: (camera, _) {
                      if ((camera.zoom - passengerMapZoom).abs() < .04) return;
                      setState(() => passengerMapZoom = camera.zoom);
                    },
                  ),
                  children: [
                    _expressMapTileLayer(context),
                    if (lines.isNotEmpty) PolylineLayer(polylines: lines),
                    if (markers.isNotEmpty) MarkerLayer(markers: markers),
                    const ExpressMapAttribution(),
                  ],
                ),
              ),
              // Franja suave detrás de la barra de estado: la hora y los iconos
              // se leen sobre el mapa y las etiquetas no se mezclan con ellos.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.paddingOf(context).top + 14,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: .86),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if ((!initialLoading || snapshot.hasError) &&
                  effectivePassengerOffers.isEmpty &&
                  hasActivePassengerService &&
                  !effectivePassengerFlowMinimized)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .72,
                      ),
                      child: _buildPassengerBottomPanel(null, data!),
                    ),
                  ),
                ),
              // Search/radar has variable content (drivers looking, offers,
              // auto-accept and actions). Give it its natural height rather
              // than the old fixed 36% sheet with an empty white bottom area.
              // AnimatedSize grows upward when rows appear and shrinks back
              // to the bottom when they disappear.
              if (!initialLoading &&
                  effectivePassengerOffers.isEmpty &&
                  !hasActivePassengerService &&
                  !effectivePassengerFlowMinimized &&
                  (compactSearching || submittingRide))
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .76,
                      ),
                      child: _buildPassengerBottomPanel(null, data),
                    ),
                  ),
                ),
              // The Taxi / Envíos chooser must size to its actual content.
              // Scrolling, when necessary on short phones, moves the *entire*
              // sheet; the card itself must never contain a vertical scroller.
              // AnimatedSize grows from the lower edge as parcel fields appear.
              if ((!initialLoading || snapshot.hasError) &&
                  data != null &&
                  data.openRide == null &&
                  effectivePassengerOffers.isEmpty &&
                  !hasActivePassengerService &&
                  !effectivePassengerFlowMinimized &&
                  !(compactSearching || submittingRide) &&
                  destination != null &&
                  routeConfirmed)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .84,
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      physics: const ClampingScrollPhysics(),
                      child: _buildPassengerBottomPanel(null, data),
                    ),
                  ),
                ),
              if ((!initialLoading || snapshot.hasError) &&
                  effectivePassengerOffers.isEmpty &&
                  !hasActivePassengerService &&
                  !effectivePassengerFlowMinimized &&
                  !(compactSearching || submittingRide) &&
                  !(data != null &&
                      data.openRide == null &&
                      destination != null &&
                      routeConfirmed))
                DraggableScrollableSheet(
                  key: ValueKey(
                    hasPassengerOffers
                        ? 'passenger-offers-' +
                            (data!.openRide?['id']?.toString() ?? 'active')
                        : (compactSearching
                                    ? 'passenger-searching-'
                                    : 'passenger-home-') +
                                panelRevision.toString(),
                  ),
                  initialChildSize: hasPassengerOffers
                      ? .72
                      : (compactSearching || submittingRide)
                          ? .36
                          : hasActivePassengerService
                              ? activePassengerPanelFraction
                              : destination == null
                                  ? homePanelFraction
                                  : routeConfirmed
                                      ? rideChooserFraction
                                      : confirmRouteFraction,
                  minChildSize: hasPassengerOffers
                      ? .52
                      : (compactSearching || submittingRide)
                          ? .36
                          : hasActivePassengerService
                              ? activePassengerPanelFraction
                              : destination == null
                                  ? homePanelFraction
                                  : routeConfirmed
                                      ? rideChooserFraction
                                      : confirmRouteFraction,
                  maxChildSize: hasPassengerOffers
                      ? .92
                      : (compactSearching || submittingRide)
                          ? .68
                          : hasActivePassengerService
                              ? activePassengerPanelFraction
                              : destination == null
                                  ? homePanelFraction
                                  : routeConfirmed
                                      ? rideChooserFraction
                                      : confirmRouteFraction,
                  snap: compactSearching ||
                      submittingRide ||
                      hasPassengerOffers,
                  snapSizes: hasPassengerOffers
                      ? const [.52, .72, .92]
                      : (compactSearching || submittingRide)
                          ? const [.36, .42, .68]
                          : null,
                  builder: (context, scrollController) {
                    if (initialLoading) {
                      return _PassengerInitialPanel(
                        controller: scrollController,
                        hasError: snapshot.hasError,
                        error: snapshot.error,
                        onRetry: _refreshHome,
                      );
                    }

                    return _buildPassengerBottomPanel(scrollController, data);
                },
              ),
              if (effectivePassengerFlowMinimized && rawPassengerFlowActive)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Material(
                      elevation: 8,
                      color: _riderSurface(context),
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        onTap: _restorePassengerFlow,
                        borderRadius: BorderRadius.circular(22),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: expressBlue.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.route_rounded,
                                  color: expressBlue,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      minimizedFlowTitle,
                                      style: TextStyle(
                                        color: _riderText(context),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      'Toca para volver al seguimiento',
                                      style: TextStyle(
                                        color: _riderMuted(context),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_upward_rounded,
                                color: expressBlue,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (hasPassengerOffers && !passengerFlowMinimized)
                Positioned.fill(
                  child: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      child: _OffersCard(
                        key: ValueKey(
                          'passenger-map-offers-' +
                              offerRide['id'].toString() +
                              '-' +
                              effectivePassengerOffers
                                  .map(_passengerOfferPresentationKey)
                                  .join('|'),
                        ),
                        ride: offerRide,
                        offers: effectivePassengerOffers,
                        viewedCount: data?.viewedCount ?? 0,
                        viewers: data?.viewers ?? const [],
                        nearbyCount: data?.nearbyDrivers.length ?? 0,
                        autoAcceptNearest: autoAcceptNearest,
                        onAutoAcceptNearest: _setAutoAcceptNearest,
                        onOffer: _selectOffer,
                        onDecline: _declineOffer,
                        onExpire: _expirePassengerOffer,
                        onCancel: () => _cancelOpenRide(offerRide!),
                      ),
                    ),
                  ),
                ),
              // Place the small map controls LAST in the Stack so the
              // full-screen, transparent quote scroller cannot intercept
              // taps on Volver or the GPS button in Taxi / Envíos.
              if (effectivePassengerOffers.isEmpty)
                Positioned(
                  top: 10,
                  left: 14,
                  right: 14,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      _CircleButton(
                        icon: passengerTripNavigationLocked
                            ? Icons.lock_rounded
                            : passengerFlowActive
                                ? Icons.arrow_back_rounded
                                : Icons.menu_rounded,
                        onPressed: passengerTripNavigationLocked
                            ? () {}
                            : passengerFlowActive
                                ? (passengerSetupFlow
                                    ? _backFromPassengerSetup
                                    : _backFromPassengerFlow)
                                : _showPassengerMenu,
                      ),
                      Expanded(
                        child: Center(
                          child: routeConfirmed &&
                                  fareQuote['dynamic_pricing_enabled'] == true
                              ? Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: _DemandPricingChip(quote: fareQuote),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      _CircleButton(
                        icon: routing
                            ? Icons.route_rounded
                            : Icons.my_location_rounded,
                        onPressed: () => _locate(resetPickupToGps: true),
                        busy: locating || routing,
                      ),
                    ],
                  ),
                ),
              ),
            
              const ExpressOfflineBanner(),
            ],
          ),
        );
      },
    );
  }


}

class _PassengerInitialPanel extends StatelessWidget {
  final ScrollController controller;
  final bool hasError;
  final Object? error;
  final VoidCallback onRetry;

  const _PassengerInitialPanel({
    required this.controller,
    required this.hasError,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      controller: controller,
      children: [
        if (hasError) ...[
          const _NoticeCard(
            icon: Icons.error_outline_rounded,
            title: 'No pudimos cargar el inicio',
            subtitle: 'Reintenta sin cerrar sesión.',
          ),
          const SizedBox(height: 8),
          if (error != null)
            Text(
              error.toString(),
              style: const TextStyle(
                color: expressMuted,
                fontSize: 11,
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ),
        ],
      ],
    );
  }
}

class _PassengerBottomPanel extends StatelessWidget {
  final ScrollController? controller;
  final _PassengerStateData data;
  final List<Map<String, dynamic>> services;
  final Map<String, dynamic> settings;
  final String? zoneName;
  final String currencyCode;
  final String serviceType;
  final bool parcelAvailable;
  final String? parcelKind;
  final ValueChanged<String> onParcelKind;
  final TextEditingController parcelSenderName;
  final TextEditingController parcelSenderPhone;
  final TextEditingController parcelRecipientName;
  final TextEditingController parcelRecipientPhone;
  final TextEditingController parcelDescription;
  final int parcelPhotoCount;
  final bool parcelPhotosUploading;
  final VoidCallback onAddParcelPhotos;
  final String category;
  final String payment;
  final num fare;
  final num minimumFare;
  final double fareIncrement;
  final bool fareReady;
  final DateTime? scheduledFor;
  final PickedLocation? pickup;
  final PickedLocation? destination;
  final double? routeDistanceKm;
  final int? routeDurationMinutes;
  final bool routing;
  final bool quoting;
  final bool creating;
  final bool routeConfirmed;
  final bool autoAcceptNearest;
  final ValueChanged<bool> onAutoAcceptNearest;
  final ValueChanged<String> onType;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onPayment;
  final ValueChanged<num> onFare;
  final ValueChanged<DateTime?> onSchedule;
  final VoidCallback onPickup;
  final VoidCallback onDestination;
  final VoidCallback onConfirmRoute;
  final VoidCallback onReviewRoute;
  final VoidCallback onRetryFare;
  final VoidCallback onCreate;
  final ValueChanged<Map<String, dynamic>> onOffer;
  final ValueChanged<Map<String, dynamic>> onDeclineOffer;
  final ValueChanged<Map<String, dynamic>> onExpireOffer;
  final ValueChanged<Map<String, dynamic>> onCancelRide;
  final ValueChanged<Map<String, dynamic>> onCancelTrip;
  final ValueChanged<Map<String, dynamic>> onCancelDelivery;
  final ValueChanged<Map<String, dynamic>> onTripTracking;
  final ValueChanged<Map<String, dynamic>> onDeliveryTracking;
  final ValueChanged<Map<String, dynamic>> onRatePending;
  final ValueChanged<Map<String, dynamic>> onSaved;
  final VoidCallback onHistory;
  final VoidCallback onSavedPlaces;

  const _PassengerBottomPanel({
    required this.controller,
    required this.data,
    required this.services,
    required this.settings,
    required this.zoneName,
    required this.currencyCode,
    required this.serviceType,
    required this.parcelAvailable,
    required this.parcelKind,
    required this.onParcelKind,
    required this.parcelSenderName,
    required this.parcelSenderPhone,
    required this.parcelRecipientName,
    required this.parcelRecipientPhone,
    required this.parcelDescription,
    required this.parcelPhotoCount,
    required this.parcelPhotosUploading,
    required this.onAddParcelPhotos,
    required this.category,
    required this.payment,
    required this.fare,
    required this.minimumFare,
    required this.fareIncrement,
    required this.fareReady,
    required this.scheduledFor,
    required this.pickup,
    required this.destination,
    required this.routeDistanceKm,
    required this.routeDurationMinutes,
    required this.routing,
    required this.quoting,
    required this.creating,
    required this.routeConfirmed,
    required this.autoAcceptNearest,
    required this.onAutoAcceptNearest,
    required this.onType,
    required this.onCategory,
    required this.onPayment,
    required this.onFare,
    required this.onSchedule,
    required this.onPickup,
    required this.onDestination,
    required this.onConfirmRoute,
    required this.onReviewRoute,
    required this.onRetryFare,
    required this.onCreate,
    required this.onOffer,
    required this.onDeclineOffer,
    required this.onExpireOffer,
    required this.onCancelRide,
    required this.onCancelTrip,
    required this.onCancelDelivery,
    required this.onTripTracking,
    required this.onDeliveryTracking,
    required this.onRatePending,
    required this.onSaved,
    required this.onHistory,
    required this.onSavedPlaces,
  });

  @override
  Widget build(BuildContext context) {
    final submittingRide = creating &&
        data.activeTrip == null &&
        data.activeDelivery == null &&
        data.openRide == null;

    // Mientras se publica, la única indicación es la carga central
    // (ExpressPublishLoader). "Ofreciendo tu tarifa" aparece solo cuando el
    // servidor ya confirmó la solicitud y hay búsqueda abierta.
    if (submittingRide) {
      return const SizedBox.shrink();
    }

    final showRideChooser = data.activeTrip == null &&
        data.activeDelivery == null &&
        data.openRide == null &&
        destination != null &&
        routeConfirmed;

    if (showRideChooser) {
      return _RideServiceChooserPanel(
        services: services,
        serviceType: serviceType,
        parcelAvailable: parcelAvailable,
        parcelKind: parcelKind,
        onParcelKind: onParcelKind,
        parcelSenderName: parcelSenderName,
        parcelSenderPhone: parcelSenderPhone,
        parcelRecipientName: parcelRecipientName,
        parcelRecipientPhone: parcelRecipientPhone,
        parcelDescription: parcelDescription,
        parcelPhotoCount: parcelPhotoCount,
        parcelPhotosUploading: parcelPhotosUploading,
        onAddParcelPhotos: onAddParcelPhotos,
        onType: onType,
        settings: settings,
        zoneName: zoneName,
        currencyCode: currencyCode,
        category: category,
        payment: payment,
        fare: fare,
        minimumFare: minimumFare,
        fareReady: fareReady,
        scheduledFor: scheduledFor,
        routeDistanceKm: routeDistanceKm,
        routeDurationMinutes: routeDurationMinutes,
        routing: routing,
        quoting: quoting,
        creating: creating,
        onReviewRoute: onReviewRoute,
        onRetryFare: onRetryFare,
        onCategory: onCategory,
        onFare: onFare,
        onEditFare: () => _editFare(context),
        onSchedule: () => _chooseSchedule(context),
        onPayment: () => _choosePayment(context),
        onCreate: onCreate,
      );
    }

    return _PanelShell(
      controller: controller,
      darkSurface: _riderHomeDark(context),
      bottomPadding: destination != null && !routeConfirmed
          ? _routeConfirmationBottomPadding(context)
          : null,
      children: [
        if (data.pendingRating != null &&
            data.activeTrip == null &&
            data.activeDelivery == null &&
            data.openRide == null) ...[
          _PendingRatingCard(
            pending: data.pendingRating!,
            onTap: () => onRatePending(data.pendingRating!),
            counterpartLabel: 'conductor',
          ),
          const SizedBox(height: 10),
        ],
        if (data.activeTrip != null)
          _PassengerActiveTripCard(
            trip: data.activeTrip!,
            driver: data.counterpart,
            driverProfile: data.driverProfile,
            vehicle: data.driverVehicle,
            adSettings: settings,
            onMap: () => onTripTracking(data.activeTrip!),
            onChat: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceChatPage(
                  service: data.service,
                  title: _expressIsParcelTrip(data.activeTrip!)
                       ? 'Chat del envío' : 'Chat del viaje',
                  tripId: data.activeTrip!['id'].toString(),
                ),
              ),
            ),
            onCall: () => ExpressPrivateVoiceCall.instance.startTripCall(
              context: context,
              service: data.service,
              trip: data.activeTrip!,
            ),
            onShare: () => shareExpressTrip(
              context,
              data.service,
              data.activeTrip!,
              data.counterpart,
              data.driverVehicle,
            ),
            onEmergency: () => raiseExpressTripEmergency(
              context,
              data.service,
              data.activeTrip!['id'].toString(),
            ),
            onPassengerOnWay: () => data.service.acknowledgeDriverWaiting(
              data.activeTrip!['id'].toString(),
            ),
            onCancel: ['driver_assigned', 'driver_arriving', 'driver_waiting']
                    .contains(data.activeTrip!['status']?.toString())
                ? () => onCancelTrip(data.activeTrip!)
                : null,
          )
        else if (data.activeDelivery != null &&
            data.activeDelivery!['courier_id'] != null)
          _ActiveCard(
            icon: Icons.local_shipping_rounded,
            title: data.counterpart?['full_name']?.toString().trim().isNotEmpty == true
                ? data.counterpart!['full_name'].toString()
                : 'Repartidor asignado',
            subtitle:
                _deliveryStatus(data.activeDelivery!['status']?.toString()),
            detail: data.driverProfile?['vehicle_summary']?.toString(),
            rating: data.driverProfile?['rating']?.toString(),
            onMap: () => onDeliveryTracking(data.activeDelivery!),
            onChat: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceChatPage(
                  service: data.service,
                  title: 'Chat del delivery',
                  deliveryId: data.activeDelivery!['id'].toString(),
                ),
              ),
            ),
            onCall: () => callExpressNumber(
              context,
              data.counterpart?['phone']?.toString(),
            ),
            dangerLabel: data.activeDelivery!['status'] == 'accepted'
                ? 'Cancelar'
                : null,
            onDanger: data.activeDelivery!['status'] == 'accepted'
                ? () => onCancelDelivery(data.activeDelivery!)
                : null,
          )
        else if (data.openRide != null &&
            _isScheduledLater(data.openRide!))
          _ScheduledRideCard(
            ride: data.openRide!,
            onCancel: () => onCancelRide(data.openRide!),
          )
        else if (data.openRide != null)
          _PassengerSearchStatusCard(
            ride: data.openRide!,
            viewedCount: data.viewedCount,
            viewers: data.viewers,
            nearbyCount: data.nearbyDrivers.length,
            autoAcceptNearest: autoAcceptNearest,
            onAutoAcceptNearest: onAutoAcceptNearest,
            onCancel: () => onCancelRide(data.openRide!),
          )
        else if (data.activeDelivery != null)
          Column(
            children: [
              const _NoticeCard(
                icon: Icons.radar_rounded,
                title: 'Buscando repartidor…',
                subtitle: 'La solicitud está activa y se actualizará automáticamente.',
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onCancelDelivery(data.activeDelivery!),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancelar delivery'),
                ),
              ),
            ],
          )
        else ...[
          if (destination == null) ...[
            Text(
              _passengerGreeting(),
              style: TextStyle(
                fontSize: 13,
                color: _riderMuted(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Center(
              child: Text(
                '¿A dónde vas?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: _riderText(context),
                  height: 1.02,
                ),
              ),
            ),
            const SizedBox(height: 11),
            _HomeDestinationSearch(
              serviceType: 'ride',
              onTap: onDestination,
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                const Expanded(
                  child: _RiderSectionTitle('Lugares guardados'),
                ),
                TextButton(
                  onPressed: onSavedPlaces,
                  child: const Text('Ver todos'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _SavedPlacesGrid(
              saved: data.saved,
              onSaved: onSaved,
              onManage: onSavedPlaces,
            ),
            const SizedBox(height: 8),
          ] else if (!routeConfirmed) ...[
            Center(
              child: Text(
              'Confirma tu ruta',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _riderText(context),
              ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Revisa los dos puntos antes de continuar. Puedes tocar cualquiera para cambiarlo.',
              style: TextStyle(
                color: _riderMuted(context),
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            _CompactRoutePoints(
              pickup: pickup,
              destination: destination!,
              onPickup: onPickup,
              onDestination: onDestination,
            ),
            if (routeDistanceKm != null &&
                routeDurationMinutes != null) ...[
              const SizedBox(height: 10),
              _RouteSummary(
                distanceKm: routeDistanceKm!,
                durationMinutes: routeDurationMinutes!,
                fare: fare,
                currencyCode: currencyCode,
                routing: routing,
                quoting: false,
                showFare: false,
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: routing ? null : onConfirmRoute,
                icon: routing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Confirmar ruta y continuar'),
                style: FilledButton.styleFrom(
                  backgroundColor: expressBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ] else ...[
            Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 74),
                    child: Text(
                      'Elige tu viaje',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: _riderText(context),
                    ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onReviewRoute,
                    child: const Text('Cambiar'),
                  ),
                ),
              ],
            ),
            if (routeDistanceKm != null &&
                routeDurationMinutes != null) ...[
              const SizedBox(height: 6),
              _RouteSummary(
                distanceKm: routeDistanceKm!,
                durationMinutes: routeDurationMinutes!,
                fare: fare,
                currencyCode: currencyCode,
                routing: routing,
                quoting: quoting,
              ),
            ],
            const SizedBox(height: 12),
            _RideOfferCard(
              fare: fare,
              currency: currencyCode,
              quoting: quoting,
              onTap: quoting ? () {} : () => _editFare(context),
            ),
            const SizedBox(height: 8),
            _RideChoiceCard(
              selected: category == 'economy',
              icon: Icons.directions_car_filled_rounded,
              title: 'Express',
              subtitle: routeDurationMinutes == null
                  ? 'Viaje económico'
                  : 'Viaje aprox. · ' + routeDurationMinutes.toString() + ' min',
              price: category == 'economy' && !quoting
                  ? _rideMoney(fare, currencyCode)
                  : null,
              onTap: () => onCategory('economy'),
            ),
            const SizedBox(height: 6),
            _RideChoiceCard(
              selected: category == 'comfort',
              icon: Icons.local_taxi_rounded,
              title: 'Comfort',
              subtitle: 'Más comodidad',
              price: category == 'comfort' && !quoting
                  ? _rideMoney(fare, currencyCode)
                  : null,
              onTap: () => onCategory('comfort'),
            ),
            const SizedBox(height: 6),
            _RideChoiceCard(
              selected: category == 'xl',
              icon: Icons.airport_shuttle_rounded,
              title: 'XL',
              subtitle: 'Más espacio',
              price: category == 'xl' && !quoting
                  ? _rideMoney(fare, currencyCode)
                  : null,
              onTap: () => onCategory('xl'),
            ),
            const SizedBox(height: 6),
            _RideChoiceCard(
              selected: category == 'motorcycle',
              icon: Icons.two_wheeler_rounded,
              title: 'Moto',
              subtitle: 'Más ágil',
              price: category == 'motorcycle' && !quoting
                  ? _rideMoney(fare, currencyCode)
                  : null,
              onTap: () => onCategory('motorcycle'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MiniSetting(
                    icon: Icons.schedule_rounded,
                    label: 'Cuándo',
                    value: scheduledFor == null
                        ? 'Ahora'
                        : _formatSchedule(scheduledFor!),
                    onTap: () => _chooseSchedule(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniSetting(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Pago',
                    value: _paymentLabel(payment),
                    onTap: () => _choosePayment(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: creating || quoting ? null : onCreate,
                icon: creating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.local_taxi_rounded),
                label: Text(
                  'Confirmar ' +
                      (category == 'economy'
                          ? 'Express'
                          : category == 'comfort'
                              ? 'Comfort'
                              : category == 'xl'
                                  ? 'XL'
                                  : 'Moto'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: expressBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _editFare(BuildContext context) async {
    final clp = currencyCode.toUpperCase() == 'CLP';
    // Use the same step returned by the authoritative Supabase fare quote.
    final step = fareIncrement > 0 ? fareIncrement : (clp ? 1.0 : 0.01);
    double rounded(num value) => double.parse(
      ((value.toDouble() / step).round() * step).toStringAsFixed(2),
    );
    final floor = minimumFare.toDouble();
    final controller = TextEditingController(
      text: clp
          ? fare.round().toString()
          : (fare.toDouble() == fare.roundToDouble()
              ? fare.round().toString()
              : fare.toStringAsFixed(2)),
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tu oferta'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(decimal: !clp),
            decoration: InputDecoration(
              labelText: clp ? 'Monto en CLP' : 'Monto en Bs',
              helperText: 'Mínimo recomendado: ' +
                  _rideMoney(floor, currencyCode) +
                  (step > 0.01 ? ' · saltos de ${step.toStringAsFixed(2)}' : ''),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
            validator: (raw) {
              final value = num.tryParse(
                (raw ?? '').trim().replaceAll(',', '.'),
              );
              if (value == null) return 'Ingresa un monto válido.';
              if (rounded(value) + .001 < floor) {
                return 'No puedes ofrecer menos de ' +
                    _rideMoney(floor, currencyCode) +
                    '.';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final value = num.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              if (value != null) Navigator.pop(dialogContext, value);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) onFare(rounded(result));
  }

  Future<void> _chooseSchedule(BuildContext context) async {
    if (settings['scheduled_rides_enabled'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Los viajes programados están desactivados temporalmente.'),
        ),
      );
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flash_on_rounded),
              title: const Text('Ahora'),
              onTap: () => Navigator.pop(sheetContext, 'now'),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Programar viaje'),
              onTap: () => Navigator.pop(sheetContext, 'schedule'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;
    if (choice == 'now') {
      onSchedule(null);
      return;
    }

    if (!context.mounted) return;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: scheduledFor ?? now.add(const Duration(hours: 1)),
    );
    if (date == null || !context.mounted) return;

    final initial = scheduledFor ?? now.add(const Duration(hours: 1));
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (selected.isBefore(DateTime.now().add(const Duration(minutes: 15)))) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Programa el viaje con al menos 15 minutos de anticipación.'),
          ),
        );
      }
      return;
    }
    onSchedule(selected);
  }

  Future<void> _choosePayment(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final dark = _riderHomeDark(sheetContext);
        final surface = dark ? const Color(0xFF171717) : Colors.white;
        final options = <Map<String, Object>>[
          if (settings['allow_cash'] != false)
            {
              'value': 'cash',
              'label': 'Efectivo',
              'icon': Icons.payments_rounded,
              'color': const Color(0xFF22C55E),
            },
          if (settings['allow_driver_qr'] == true)
            {
              'value': 'driver_qr',
              'label': 'QR del conductor',
              'icon': Icons.qr_code_2_rounded,
              'color': const Color(0xFF0E9384),
            },
          if (settings['allow_card'] == true)
            {
              'value': 'card',
              'label': 'Tarjeta',
              'icon': Icons.credit_card_rounded,
              'color': expressBlue,
            },
          if (settings['allow_wallet'] == true)
            {
              'value': 'wallet',
              'label': 'Billetera Express',
              'icon': Icons.account_balance_wallet_rounded,
              'color': const Color(0xFF7A2CF3),
            },
          if (settings['allow_pagorut'] == true)
            {
              'value': 'pagorut',
              'label': 'QR Bolivia',
              'icon': Icons.account_balance_rounded,
              'color': const Color(0xFF0E9384),
            },
          if (settings['allow_mercadopago'] == true)
            {
              'value': 'mercado_pago',
              'label': 'Mercado Pago',
              'icon': Icons.wallet_rounded,
              'color': const Color(0xFF159BD7),
            },
          if (settings['allow_santander'] == true)
            {
              'value': 'santander',
              'label': 'Banco Santander',
              'icon': Icons.account_balance_rounded,
              'color': const Color(0xFFD92D20),
            },
          if (settings['allow_mach'] == true)
            {
              'value': 'mach',
              'label': 'MACH',
              'icon': Icons.phone_android_rounded,
              'color': const Color(0xFF6941C6),
            },
          if (settings['allow_tenpo'] == true)
            {
              'value': 'tenpo',
              'label': 'Tenpo',
              'icon': Icons.phone_android_rounded,
              'color': const Color(0xFFF79009),
            },
        ];

        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 9),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dark
                          ? const Color(0xFF4B5563)
                          : const Color(0xFFD0D5DD),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Métodos de pago',
                            style: TextStyle(
                              color: _riderText(sheetContext),
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: Icon(
                            Icons.close_rounded,
                            color: _riderText(sheetContext),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        options.length <= 1
                            ? 'Este es el método de pago disponible para tu viaje.'
                            : 'Elige cómo prefieres pagar tu viaje.',
                        style: TextStyle(
                          color: _riderMuted(sheetContext),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final value = option['value']! as String;
                        final color = option['color']! as Color;
                        final selectedOption = payment == value;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: selectedOption
                                ? expressBlue.withValues(alpha: .14)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Material(type: MaterialType.transparency, child: ListTile(
                            dense: true,
                            minVerticalPadding: 8,
                            leading: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                option['icon']! as IconData,
                                color: color,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              option['label']! as String,
                              style: TextStyle(
                                color: _riderText(sheetContext),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            trailing: selectedOption
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: expressBlue,
                                  )
                                : null,
                            onTap: () => Navigator.pop(sheetContext, value),
                          )),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) onPayment(selected);
  }
}

// Resumen liviano: un RPC de historial cada 2 minutos, no en cada punto GPS.
// Los importes corresponden únicamente a viajes completados del conductor.
class _DriverDailyEarningsBadge extends StatefulWidget {
  final ExpressService service;
  final VoidCallback onDetails;

  const _DriverDailyEarningsBadge({
    required this.service,
    required this.onDetails,
  });

  @override
  State<_DriverDailyEarningsBadge> createState() =>
      _DriverDailyEarningsBadgeState();
}

class _DriverDailyEarningsBadgeState extends State<_DriverDailyEarningsBadge> {
  Timer? refreshTimer;
  bool showAmount = true;
  int rides = 0;
  int deliveries = 0;
  Map<String, num> amounts = <String, num>{};
  DateTime? lastDay;
  bool fetching = false;
  bool loaded = false;
  bool loadFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final today = DateTime.now();
      final changedDay = lastDay == null ||
          lastDay!.year != today.year || lastDay!.month != today.month ||
          lastDay!.day != today.day;
      if (changedDay) {
        // El contador reinicia con el día local, el historial permanece.
        setState(() {
          rides = 0;
          deliveries = 0;
          amounts = <String, num>{};
        });
      }
      if (changedDay || today.minute.isEven) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (fetching) return;
    fetching = true;
    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      // One aggregate: counts and amounts only, never 400 full records.
      final response = await widget.service.driverDailyIncome(
        from: dayStart,
        to: DateTime(now.year, now.month, now.day + 1),
      );
      if (response['channel'] != widget.service.runtimeChannel) {
        throw StateError('El servidor devolvió otro entorno.');
      }
      final rawTotals = response['totals'];
      if (rawTotals is! Map) {
        throw const FormatException('Totales de ingresos inválidos.');
      }
      final totals = <String, num>{};
      for (final entry in rawTotals.entries) {
        final amount = asDouble(entry.value);
        if (amount == null || !amount.isFinite) continue;
        totals[entry.key.toString().toUpperCase()] = amount;
      }
      final count = (response['trips'] as num?)?.toInt() ?? 0;
      final deliveryCount = (response['deliveries'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      final currentDate = DateTime.now();
      // Responses from before midnight must never overwrite the new day.
      if (currentDate.year != now.year || currentDate.month != now.month ||
          currentDate.day != now.day) return;
      setState(() {
        lastDay = now;
        rides = count;
        deliveries = deliveryCount;
        amounts = totals;
        loaded = true;
        loadFailed = false;
      });
      _summaryEntry?.markNeedsBuild();
    } catch (_) {
      // Do not display a fake zero when the backend is unavailable.
      if (mounted) {
        setState(() => loadFailed = true);
        _summaryEntry?.markNeedsBuild();
      }
    } finally {
      fetching = false;
    }
  }

  @override
  void dispose() {
    final entry = _summaryEntry;
    _summaryEntry = null;
    entry?.remove();
    entry?.dispose();
    refreshTimer?.cancel();
    super.dispose();
  }

  OverlayEntry? _summaryEntry;

  void _dismissSummary() {
    final entry = _summaryEntry;
    if (entry == null) return;
    _summaryEntry = null;
    entry.remove();
    entry.dispose();
    if (mounted) setState(() {});
  }

  void _toggleAmount() {
    setState(() => showAmount = !showAmount);
    _summaryEntry?.markNeedsBuild();
  }

  // The white card expands from the earnings capsule, never from the bottom.
  void _showSummary() {
    if (_summaryEntry != null) { _dismissSummary(); return; }
    final media = MediaQuery.of(context);
    final render = context.findRenderObject();
    final y = render is RenderBox
        ? render.localToGlobal(Offset.zero).dy : media.padding.top + 12.0;
    final top = math.max(media.padding.top + 6.0, y - 8.0);
    final maxHeight = math.max(
        180.0, media.size.height - top - media.padding.bottom - 12.0);
    final dark = _riderHomeDark(context);
    final surfaceColor = dark ? const Color(0xFF202329) : Colors.white;
    final foregroundColor = dark ? const Color(0xFFF8FAFC)
        : const Color(0xFF101828);
    final mutedColor = dark ? const Color(0xFFBBC2CF)
        : const Color(0xFF475467);
    _summaryEntry = OverlayEntry(
      builder: (overlayContext) => Material(
        color: Colors.transparent,
        child: Stack(children: [
          Positioned.fill(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissSummary,
            // Sin velo oscuro: el resumen se cierra tocando fuera, sin oscurecer el mapa.
            child: const SizedBox.expand(),
          )),
          Positioned(
            top: top, left: 14, right: 14,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Material(
                elevation: 20,
                color: surfaceColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(
                    color: dark ? const Color(0xFF454B56)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Text('Resumen de hoy',
                          style: TextStyle(color: foregroundColor,
                            fontSize: 20, fontWeight: FontWeight.w800))),
                        IconButton(
                          tooltip: showAmount
                              ? 'Ocultar ganancias' : 'Mostrar ganancias',
                          onPressed: _toggleAmount,
                          icon: Icon(showAmount
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          color: foregroundColor,
                        ),
                      ]),
                      const SizedBox(height: 14),
                      Divider(height: 1,
                        color: dark ? const Color(0xFF414751)
                            : const Color(0xFFE5E7EB)),
                      const SizedBox(height: 22),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Viajes completados', style: TextStyle(
                                color: mutedColor, fontSize: 13)),
                              const SizedBox(height: 10),
                              Text(loaded ? '$rides' : '—', style: TextStyle(
                                color: foregroundColor, fontSize: 27,
                                fontWeight: FontWeight.w800)),
                              if (loaded && deliveries > 0) ...[
                                const SizedBox(height: 8),
                                Text('Entregas completadas: $deliveries',
                                  style: TextStyle(
                                    color: mutedColor, fontSize: 11)),
                              ],
                            ],
                          )),
                          const SizedBox(width: 16),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ganancias', style: TextStyle(
                                color: mutedColor, fontSize: 13)),
                              const SizedBox(height: 10),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  showAmount
                                      ? (loaded ? _amountLabel() : '—')
                                      : '••••',
                                  maxLines: 1,
                                  style: TextStyle(color: foregroundColor,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          )),
                        ],
                      ),
                      if (loadFailed) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'No se pudieron actualizar las ganancias.',
                          style: TextStyle(color: Color(0xFFEF4444)),
                        ),
                      ],
                      const SizedBox(height: 22),
                      InkWell(
                        onTap: () {
                          _dismissSummary();
                          widget.onDetails();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 2),
                          child: Row(children: [
                            Expanded(child: Text(
                              'Ver detalle diario y semanal',
                              style: TextStyle(
                                color: mutedColor, fontSize: 13,
                                fontWeight: FontWeight.w600))),
                            Icon(Icons.arrow_forward_rounded,
                              size: 20, color: foregroundColor),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
    Overlay.of(context).insert(_summaryEntry!);
    setState(() {});
  }

  String _amountLabel() {
    if (amounts.isEmpty) return '0';
    return amounts.entries.map((entry) =>
      _rideMoney(entry.value, entry.key)).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final text = !loaded ? '—' : _amountLabel();
    // Width is defined by the independently centered header slot, not by
    // the online-status badge or the amount's number of digits.
    return Material(
      color: const Color(0xFF22252D).withValues(alpha: .98),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(44),
        side: BorderSide(
          color: const Color(0xFF7B8390).withValues(alpha: .75),
          width: 1.2,
        ),
      ),
      elevation: 5,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showSummary,
        borderRadius: BorderRadius.circular(44),
        child: SizedBox(
          width: double.infinity,
          height: 74,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  // Equal leading/trailing space keeps the amount centered
                  // with only the chevron visible on the right.
                  const SizedBox(width: 21),
                  Expanded(child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(showAmount ? text : '••••',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 21,
                        fontWeight: FontWeight.w900)),
                  )),
                  const SizedBox(width: 2),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 19, color: Colors.white),
                ]),
                const SizedBox(height: 5),
                const Text('Ganancia de hoy', maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11, color: Color(0xFFE5E7EB),
                    fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DriverMapHome extends StatefulWidget {
  final ExpressService service;
  final int revision;
  final VoidCallback onChanged;
  final VoidCallback onSwitchMode;
  final VoidCallback onHistory;
  final VoidCallback onEarnings;
  final VoidCallback onProfile;
  final VoidCallback onSafety;
  final ValueChanged<int>? onRequestCountChanged;
  final ValueChanged<bool>? onOfferPendingChanged;

  const DriverMapHome({
    super.key,
    required this.service,
    required this.revision,
    required this.onChanged,
    required this.onSwitchMode,
    required this.onHistory,
    required this.onEarnings,
    required this.onProfile,
    required this.onSafety,
    this.onRequestCountChanged,
    this.onOfferPendingChanged,
  });

  @override
  State<DriverMapHome> createState() => _DriverMapHomeState();
}

class _DriverMapHomeState extends State<DriverMapHome>
    with WidgetsBindingObserver {
  // Ventana flotante de ofertas: el conductor la activa voluntariamente y
  // Admin debe tenerla encendida. Sin permiso o sin ajuste, no muestra nada.
  late final DriverFloatingOfferController _floatingOffers =
      DriverFloatingOfferController(
    bridge: DriverFloatingOfferBridge(onBubbleEvent: _onBubbleEvent),
    settings: DriverFloatingOfferSettings(accountId: widget.service.userId),
  );

  /// Burbuja de acceso directo: 'dismissed' recuerda la decisión del conductor
  /// hasta que vuelva a abrir Express o reactive el ajuste. 'open_app' no
  /// requiere nada más: Android trae Express al frente.
  void _onBubbleEvent(String action) {
    if (action == 'dismissed') {
      unawaited(_floatingOffers.settings.setBubbleDismissed(true));
    }
  }
  bool _appInForeground = true;
  String? _pendingFloatingFocusId;
  DateTime? _pendingFloatingFocusAt;
  bool _pendingFocusFromNotification = false;

  bool _floatingAdminEnabled = false;
  // Error de consulta distinto de "deshabilitado": no se cachea y el modal lo dice.
  bool _floatingAdminUnavailable = false;
  DateTime? _floatingAdminCheckedAt;

  Future<bool> _loadFloatingOfferAdminFlag({bool force = false}) async {
    final now = DateTime.now().toUtc();
    if (!force && !_floatingAdminUnavailable && _floatingAdminCheckedAt != null &&
        now.difference(_floatingAdminCheckedAt!) < const Duration(seconds: 20)) {
      return _floatingAdminEnabled;
    }
    bool enabled = false;
    bool unavailable = false;
    try {
      final raw = await supabase.rpc(
        'driver_floating_offer_config',
        params: {'p_channel': ExpressRuntimeChannel.name},
      );
      enabled = raw == true;
    } catch (error) {
      // Fail closed: sin overlay mientras la consulta no responda.
      unavailable = true;
      debugPrint('[EXPRESS_DIAG] floating_admin_config_error channel=${ExpressRuntimeChannel.name} error=$error');
    }
    _floatingAdminUnavailable = unavailable;
    _floatingAdminCheckedAt = unavailable ? null : DateTime.now().toUtc();
    _floatingAdminEnabled = enabled;
    if (mounted && !_appInForeground) unawaited(_syncFloatingOffer());
    return enabled;
  }

  /// Select only authorized requests returned by the existing Taxi/Envíos APIs.
  FloatingOfferCard? _firstFloatingOfferCard() {
    final data = cachedData;
    if (data == null) return null;
    return firstDriverFloatingCard(
      rides: data.rides,
      deliveries: data.deliveries,
      now: DateTime.now().toUtc(),
      formatPrice: (amount, currency) => _rideMoney(amount, currency),
    );
  }

  /// Centra al conductor en el área del mapa visible sobre su panel inferior compacto.
  void _centerDriverMap(LatLng point, double zoom) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final offset = visibleAreaCenterOffset(
      viewportHeight: size.height,
      topInset: MediaQuery.paddingOf(context).top + 72,
      bottomOccludedHeight: .36 * size.height,
    );
    try {
      mapController.move(point, zoom, offset: offset);
    } catch (_) {}
  }

  Future<void> _syncFloatingOffer() async {
    if (!mounted) return;
    // Prefetched while active: no new network RPC required in paused.
    if (!_floatingAdminEnabled) {
      await _floatingOffers.close();
      return;
    }
    final data = cachedData;
    final online = data?.profile['online_status'] == 'online' &&
        data?.profile['approval_status'] == 'approved';
    await _floatingOffers.sync(
      offer: _firstFloatingOfferCard(),
      driverOnline: online,
      driverAvailable: online &&
          data?.activeTrip == null &&
          data?.activeDelivery == null &&
          driverOfferPendingRideId == null,
      appInForeground: _appInForeground,
      now: DateTime.now().toUtc(),
    );
  }

  /// Respaldo breve mientras una barra está realmente dibujada en Android.
  /// Realtime la retira inmediatamente; esta consulta autenticada detecta
  /// cambios perdidos, incluso si la barra nació por FCM y no por Flutter.
  /// Sin conexión se conserva hasta su vencimiento visual (máximo 30 s).
  bool _driverFloatingBarCheckInFlight = false;
  Timer? _driverFloatingBarValidityTimer;

  Future<void> _checkActiveDriverFloatingBar() async {
    if (!mounted || _appInForeground || _driverFloatingBarCheckInFlight) {
      return;
    }
    _driverFloatingBarCheckInFlight = true;
    try {
      final offerId = await _floatingOffers.bridge.activeOfferId();
      if (offerId == null || offerId.isEmpty) return;

      final ride = await supabase
          .from('ride_requests')
          .select('status,expires_at,channel')
          .eq('id', offerId)
          .maybeSingle();
      if (!mounted || _appInForeground) return;

      final status = ride?['status']?.toString();
      final expiresAt =
          DateTime.tryParse(ride?['expires_at']?.toString() ?? '')?.toUtc();
      final live = ride != null &&
          (status == 'searching' || status == 'offers_received') &&
          expiresAt != null &&
          expiresAt.isAfter(DateTime.now().toUtc()) &&
          ride['channel']?.toString() == ExpressRuntimeChannel.name;

      if (!live) {
        final closed = await _floatingOffers.invalidateOffer(offerId);
        if (closed && mounted) {
          debugPrint('[EXPRESS_DIAG] bar_backend_invalidated id=$offerId');
          _refreshDriverHome();
        }
      }
    } catch (error) {
      // No confundir una caída de red con una cancelación del pasajero.
      debugPrint('[EXPRESS_DIAG] bar_backend_check_failed error=$error');
    } finally {
      _driverFloatingBarCheckInFlight = false;
    }
  }

  // Mientras el detalle esté abierto, comprobación liviana de respaldo.
  // Realtime sigue siendo la vía principal; este sondeo solo se ejecuta
  // con popup visible y evita dejar aceptar una oferta ya cancelada.
  bool _driverPopupValidityCheckInFlight = false;

  Future<void> _checkDriverPopupValidity() async {
    final id = driverRequestPopupId;
    if (!mounted || !_appInForeground || id == null ||
        _driverPopupValidityCheckInFlight) return;
    _driverPopupValidityCheckInFlight = true;
    try {
      final ride = await supabase
          .from('ride_requests')
          .select('status,expires_at,channel')
          .eq('id', id)
          .maybeSingle();
      if (!mounted || !_appInForeground || driverRequestPopupId != id) return;
      final status = ride?['status']?.toString();
      final expiry = DateTime.tryParse(
        ride?['expires_at']?.toString() ?? '',
      )?.toUtc();
      final available = ride != null &&
          (status == 'searching' || status == 'offers_received') &&
          expiry != null &&
          expiry.isAfter(DateTime.now().toUtc()) &&
          ride['channel']?.toString() == ExpressRuntimeChannel.name;
      if (!available) {
        _closeDriverRequestPopup(showNext: false);
        _dropUnavailableRide(id);
        unawaited(_floatingOffers.invalidateOffer(id));
        _refreshDriverHome();
      }
    } catch (error) {
      // Ante una caída de red no asumir que el pasajero canceló.
      debugPrint('[EXPRESS_DIAG] driver_popup_check_failed error=$error');
    } finally {
      _driverPopupValidityCheckInFlight = false;
    }
  }

  /// Only opens a fresh authorized offer in the original bid UI.
  void _onFloatingOfferFocus() {
    final id = driverFloatingOfferFocus.value;
    if (id == null || !mounted) return;
    driverFloatingOfferFocus.value = null;
    unawaited(_floatingOffers.close());
    // Android sends Accept before bringing its Activity to the foreground.
    // Keep the action only in this mounted driver's State, never globally.
    _pendingFloatingFocusId = id;
    _pendingFloatingFocusAt = DateTime.now().toUtc();
    _pendingFocusFromNotification = false;
    if (_appInForeground) _consumePendingFloatingFocus();
  }

  /// Tocar el aviso de Android abre el detalle directamente. La ventana
  /// flotante es opcional y su ajuste no bloquea esta apertura; la oferta
  /// igual se revalida en el servidor antes de mostrarse.
  void _onNotificationOfferFocus() {
    final id = driverNotificationOfferFocus.value;
    if (id == null || !mounted) return;
    driverNotificationOfferFocus.value = null;
    _pendingFloatingFocusId = id;
    _pendingFloatingFocusAt = DateTime.now().toUtc();
    _pendingFocusFromNotification = true;
    if (_appInForeground) _consumePendingFloatingFocus();
  }

  void _consumePendingFloatingFocus() {
    // A cold Android launch can resume before the driver's first query
    // completes. Keep the user's tap pending until the screen has a usable
    // authenticated state, rather than silently discarding it.
    if (!mounted || !_appInForeground || cachedData == null) return;
    final id = _pendingFloatingFocusId;
    final at = _pendingFloatingFocusAt;
    final fromNotification = _pendingFocusFromNotification;
    _pendingFloatingFocusId = null;
    _pendingFloatingFocusAt = null;
    _pendingFocusFromNotification = false;
    if (id == null || at == null ||
        !driverFloatingActionIsRecent(at, DateTime.now().toUtc())) return;
    unawaited(_revalidateFloatingOfferFocus(
      id,
      fromNotification: fromNotification,
    ));
  }

  /// When Android starts a fresh Flutter engine after tapping an overlay,
  /// the in-memory MethodChannel event has been lost. Read the native tap
  /// only after the driver data is initialized. Every action is revalidated
  /// for the signed-in account, current channel and server-side expiry.
  Future<void> _restoreNativeFloatingOfferOpen() async {
    // Consume native intent independently of expensive Supabase initialization.
    // The offer itself is not opened until cachedData is ready and a fresh
    // authorized, unexpired row has been fetched from the backend.
    final id = await _floatingOffers.bridge.consumePendingOpen();
    if (!mounted || id == null || id.isEmpty) return;
    _pendingFloatingFocusId = id;
    _pendingFloatingFocusAt = DateTime.now().toUtc();
    unawaited(AppErrorReporter.event(
      'FLOATING_OFFER_TAP_RECOVERED',
      source: 'driver_floating_offer_open',
      screen: 'driver_home',
      context: {'foreground': _appInForeground},
    ));
    if (_appInForeground) _consumePendingFloatingFocus();
  }

  void _reportFloatingOfferBlock(String reason) {
    unawaited(AppErrorReporter.event(
      'FLOATING_OFFER_OPEN_BLOCKED',
      source: 'driver_floating_offer_open',
      screen: 'driver_home',
      context: {'reason': reason},
    ));
    if (mounted && _appInForeground) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text(
          'No se pudo abrir el detalle. Revisa la oferta en Solicitudes.',
        )),
      );
    }
  }

  Future<void> _revalidateFloatingOfferFocus(
    String id, {
    bool fromNotification = false,
  }) async {
    final account = widget.service.userId;
    if (!mounted || !_appInForeground ||
        supabase.auth.currentUser?.id != account) {
      _reportFloatingOfferBlock('not_foreground_or_wrong_account');
      return;
    }
    var data = cachedData;
    if (data == null ||
        data.profile['online_status'] != 'online' ||
        data.profile['approval_status'] != 'approved' ||
        data.activeTrip != null || data.activeDelivery != null ||
        driverRequestPopupId != null || driverDeliveryPopupId != null) {
      // Si el popup ya muestra esta misma oferta (llegó sola por tiempo real),
      // el toque solo la enfoca: no es un bloqueo ni debe mostrar error.
      if (driverRequestPopupId != id) {
        _reportFloatingOfferBlock('driver_unavailable_or_popup_busy');
      }
      return;
    }
    try {
      // The driver or Admin may have disabled permission after the overlay
      // appeared. Never open a stale notification from an old authorization.
      final adminEnabled = await _loadFloatingOfferAdminFlag(force: true);
      final driverEnabled = await _floatingOffers.settings.isEnabled();
      final androidGranted = await _floatingOffers.bridge.hasPermission();
      // Los avisos de Android no dependen del overlay; el permiso y el ajuste
      // solo bloquean los toques de la ventana flotante.
      if (!fromNotification &&
          (!adminEnabled || !driverEnabled || !androidGranted)) {
        _reportFloatingOfferBlock(!adminEnabled
            ? 'admin_setting_disabled'
            : !driverEnabled
                ? 'driver_setting_disabled'
                : 'android_permission_disabled');
        return;
      }
      if (!mounted || supabase.auth.currentUser?.id != account) return;
      // Refetch each authorized service independently. One failing endpoint
      // must never block a valid Taxi request from opening (or vice versa).
      // Never open a cached offer without a successful fresh server response.
      List<Map<String, dynamic>> rides = [];
      List<Map<String, dynamic>> deliveries = [];
      try {
        rides = await widget.service.availableRideRequests();
      } catch (error, stack) {
        unawaited(AppErrorReporter.capture(
          error, stack,
          source: 'driver_floating_offer_open',
          screen: 'driver_home',
          eventName: 'FLOATING_RIDE_REFRESH_FAILED',
          fatal: false,
        ));
      }
      try {
        deliveries = await widget.service.availableDeliveries();
      } catch (error, stack) {
        unawaited(AppErrorReporter.capture(
          error, stack,
          source: 'driver_floating_offer_open',
          screen: 'driver_home',
          eventName: 'FLOATING_DELIVERY_REFRESH_FAILED',
          fatal: false,
        ));
      }
      if (!mounted || !_appInForeground ||
          widget.service.userId != account ||
          supabase.auth.currentUser?.id != account) return;
      data = cachedData;
      if (data == null ||
          data.profile['online_status'] != 'online' ||
          data.profile['approval_status'] != 'approved' ||
          data.activeTrip != null || data.activeDelivery != null) return;
      final target = resolveFloatingOfferFocus(
        offerId: id,
        rides: rides,
        deliveries: deliveries,
        driverOnline: true,
        now: DateTime.now().toUtc(),
      );
      if (target == null) {
        unawaited(AppErrorReporter.event(
          'FLOATING_OFFER_NO_LONGER_AVAILABLE',
          source: 'driver_floating_offer_open',
          screen: 'driver_home',
          context: {'ride_refresh_ok': rides.isNotEmpty,
                    'delivery_refresh_ok': deliveries.isNotEmpty},
        ));
        if (mounted && _appInForeground) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text(
              'Esta solicitud ya no está disponible. Revisa Solicitudes.',
            )),
          );
        }
        return;
      }
      if (target.kind == FloatingOfferFocusKind.taxi) {
        final workKey = target.item['service_mode'] == 'parcel'
            ? 'parcel' : 'ride';
        if (!driverApprovedWorkKeys.contains(workKey)) {
          _reportFloatingOfferBlock('taxi_or_parcel_not_authorized');
          return;
        }
        _openRequestFromList(target.item);
        if (driverRequestPopupId != id) {
          _reportFloatingOfferBlock('taxi_popup_not_presented');
          return;
        }
      } else {
        if (!driverApprovedWorkKeys.contains(_deliveryCategory(target.item)) ||
            !expressPrimaryDriverMayReceiveDelivery(
                target.item, driverApprovedWorkKeys)) {
          _reportFloatingOfferBlock('delivery_not_authorized');
          return;
        }
        _openDeliveryRequestPopup(target.item, automatic: false);
        if (driverDeliveryPopupId != id) {
          _reportFloatingOfferBlock('delivery_popup_not_presented');
          return;
        }
      }
      unawaited(AppErrorReporter.event(
        'FLOATING_OFFER_POPUP_PRESENTED',
        source: 'driver_floating_offer_open',
        screen: 'driver_home',
      ));
    } catch (error, stack) {
      // The native tap was genuine, but Supabase may have disconnected while
      // Android resumed the Activity. Do not leave a silent/blank result.
      unawaited(AppErrorReporter.capture(
        error,
        stack,
        source: 'driver_floating_offer_open',
        screen: 'driver_home',
        eventName: 'FLOATING_OFFER_OPEN_FAILED',
        fatal: false,
      ));
      if (mounted && _appInForeground) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text(
            'No se pudo abrir la solicitud. Comprueba tu conexión e inténtalo desde Solicitudes.',
          )),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    if (_appInForeground) {
      ExpressCallPresence.start(widget.service);
      unawaited(syncDriverPushOverlayState(widget.service));
      unawaited(syncOverlayCallPreference(widget.service).then((granted) {
        if (mounted) setState(() => overlayAllowed = granted);
      }));
      // Nueva sesión en primer plano: la decisión de descartar la burbuja expira.
      unawaited(_floatingOffers.settings.setBubbleDismissed(false));
      unawaited(_floatingOffers.close());
      unawaited(_checkDriverPopupValidity());
      _consumePendingFloatingFocus();
      unawaited(_restoreNativeFloatingOfferOpen());
    } else if (state == AppLifecycleState.paused) {
      ExpressCallPresence.stop();
      unawaited(_syncFloatingOffer());
    }
  }

  // Sobreposición activa: muestra las opciones que dependen de ella (burbuja, ofertas emergentes, llamadas).
  bool overlayAllowed = false;
  String? overlayPromptTripId;
  final mapController = MapController();
  final locationService = const ExpressLocationService();
  StreamSubscription? positionSubscription;
  StreamSubscription<String>? driverForegroundPushSubscription;
  RealtimeChannel? driverRideRequestsChannel;
  RealtimeChannel? driverDeliveriesChannel;
  RealtimeChannel? driverNotificationsChannel;
  RealtimeChannel? driverZoneServicesChannel;
  Timer? timer;

  LatLng? current;
  double driverMapZoom = 15.0;
  bool busy = false;
  bool driverRefreshInFlight = false;
  bool driverPriorityEnforced = false;
  Map<String, dynamic> driverPrioritySummary = const {};
  _DriverStateData? cachedData;
  late Future<_DriverStateData> driverFuture;
  final ValueNotifier<LatLng?> driverPosition = ValueNotifier<LatLng?>(null);
  final driverMapHeading = MapVehicleHeading();
  String driverMapVehicleType = 'unknown';
  final Set<String> viewedRideRequestIds = <String>{};
  bool viewedRideRequestIdsLoaded = false;
  String? driverRequestPopupId;
  // The shell hides navigation for *every* foreground driver task, not just
  // the 30-second offer acceptance wait.
  bool? lastReportedDriverFocusLocked;
  bool driverRequestPopupAutomatic = false;
  int driverRequestPopupRemaining = 0;
  DateTime? driverRequestPopupExpiresAt;
  Timer? driverRequestPopupTimer;
  String? driverOfferPendingRideId;
  int driverOfferPendingRemaining = 0;
  DateTime? driverOfferPendingExpiresAt;
  Timer? driverOfferPendingTimer;
  List<LatLng> driverPopupRoadRoute = const [];
  bool driverRequestQueueAdvancing = false;
  // Work-service approval belongs to Admin, not the selected vehicle category.
  Set<String> driverApprovedWorkKeys = {'ride'};
  DateTime? driverApprovedWorkCheckedAt;
  String? driverDeliveryPopupId;
  bool driverDeliveryPopupAutomatic = false;
  int driverDeliveryPopupRemaining = 0;
  DateTime? driverDeliveryPopupExpiresAt;
  Timer? driverDeliveryPopupTimer;
  final Set<String> viewedDeliveryRequestIds = <String>{};

  Future<void> _loadDriverApprovedWork() async {
    final now = DateTime.now().toUtc();
    if (driverApprovedWorkCheckedAt != null &&
        now.difference(driverApprovedWorkCheckedAt!) < const Duration(seconds: 45)) {
      return;
    }
    driverApprovedWorkCheckedAt = now;
    try {
      final raw = await supabase.rpc('my_driver_work_permissions',
          params: {'p_channel': ExpressRuntimeChannel.name});
      if (raw is! List) return;
      // Restaurant deliveries use the same driver experience and require the
      // separate `market` approval just like parcels require `parcel`.
      final approved = expressPrimaryDriverApprovedServices(
        raw.whereType<Map>().where(
          (row) => row['status']?.toString() == 'approved',
        ).map((row) => row['service_key']?.toString() ?? ''),
      );
      driverApprovedWorkKeys = approved;
    } catch (_) {
      // Before the new RPC is deployed, do not expose unapproved courier work.
      driverApprovedWorkKeys = {'ride'};
    }
  }

  String _deliveryCategory(Map<String, dynamic> delivery) =>
      delivery['marketplace_order_id'] == null ? 'parcel' : 'market';

  // Same Taxi presentation and route, with courier data mapped to its keys.
  Map<String, dynamic> _asDriverRequest(Map<String, dynamic> delivery) => {
        ...delivery,
        '_express_delivery': true,
        'destination_address': delivery['dropoff_address'],
        'destination_latitude': delivery['dropoff_latitude'],
        'destination_longitude': delivery['dropoff_longitude'],
        'category': delivery['marketplace_order_id'] == null ? 'Envíos' : 'Restaurante',
      };

  List<Map<String, dynamic>> _deliveryItemsFor(
      List<Map<String, dynamic>> deliveries, String category) {
    return deliveries.where((d) => _deliveryCategory(d) == category)
        .map((d) => <String, dynamic>{
          ...d,
          '_express_delivery': true,
          'pickup_address': d['pickup_address'],
          'destination_address': d['dropoff_address'],
          'destination_latitude': d['dropoff_latitude'],
          'destination_longitude': d['dropoff_longitude'],
          'category': category == 'parcel' ? 'Envíos' : 'Restaurante',
        }).toList();
  }

  bool driverRideActionBusy = false;
  String? lastAnimatedDriverTripId;
  String? lastAnimatedDriverTripStatus;
  String? driverMapTripStageKey;
  String? driverActiveRoadRouteKey;
  List<LatLng> driverActiveRoadRoute = const [];
  bool driverActiveRoadRouteLoading = false;
  LatLng? driverLastCameraPoint;
  DateTime? driverLastCameraAt;
  bool driverFollowLocation = true;
  bool driverMapContextLoading = false;
  List<Map<String, dynamic>> driverHeatCells = const [];
  Timer? driverHeatTimer;
  DateTime? driverLastLocationSyncAt;
  LatLng? driverLastSyncedPoint;
  double? driverLastSyncedHeading;
  bool driverLocationSyncInFlight = false;
  bool? driverTrackingHighFrequency;
  DateTime? driverPriorityLoadedAt;
  DateTime? driverPendingRatingLoadedAt;
  final Set<String> driverAddressHydrationInFlight = <String>{};

  // One scoped backend aggregation every ~90s, never per GPS point.
  Future<void> _refreshDriverMapContext() async {
    if (driverMapContextLoading || !mounted) return;
    driverMapContextLoading = true;
    try {
      final contextData = await widget.service.driverHeatmapContext();
      if (!mounted) return;
      final raw = contextData['heat'];
      final cells = raw is List ? raw.whereType<Map>()
          .map((row) => Map<String,dynamic>.from(row)).toList()
          : <Map<String,dynamic>>[];
      setState(() => driverHeatCells = cells);
      // Demand-zone bounds must not override the driver's street-level zoom.
    } catch (_) {
      // Network outages keep the last valid map, never crash driver mode.
    } finally {
      driverMapContextLoading = false;
    }
  }

  void _refreshDriverActiveRoadRoute(
    String tripId,
    String status,
    LatLng from,
    LatLng target,
  ) {
    final key = tripId + ':' + status + ':' +
        (from.latitude * 10000).round().toString() + ':' +
        (from.longitude * 10000).round().toString();
    if (driverActiveRoadRouteKey == key || driverActiveRoadRouteLoading) {
      return;
    }
    driverActiveRoadRouteLoading = true;
    unawaited(() async {
      try {
        final points = await _expressRoadRoute(from, target);
        if (!mounted) return;
        driverActiveRoadRouteKey = key;
        setState(() => driverActiveRoadRoute = points);
      } finally {
        driverActiveRoadRouteLoading = false;
      }
    }());
  }

  LatLng? _driverTripTarget(Map<String, dynamic>? trip) {
    if (trip == null) return null;
    final rawRide = trip['ride_requests'];
    if (rawRide is! Map) return null;
    final ride = Map<String, dynamic>.from(rawRide);
    final status = trip['status']?.toString() ?? 'driver_assigned';
    final beforePickup = status == 'driver_assigned' ||
        status == 'driver_arriving' ||
        status == 'driver_waiting';
    final lat = asDouble(
      ride[beforePickup ? 'pickup_latitude' : 'destination_latitude'],
    );
    final lng = asDouble(
      ride[beforePickup ? 'pickup_longitude' : 'destination_longitude'],
    );
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  void _followActiveDriverTrip(LatLng point) {
    final trip = cachedData?.activeTrip;
    final target = _driverTripTarget(trip);
    if (target == null) return;

    final now = DateTime.now();
    final last = driverLastCameraPoint;
    final elapsed = driverLastCameraAt == null
        ? const Duration(days: 1)
        : now.difference(driverLastCameraAt!);
    final movedKm = last == null
        ? double.infinity
        : (_pickupDistanceKm(last, point.latitude, point.longitude) ??
            double.infinity);
    // Keep GPS markers live without repeatedly refitting the viewport. Small
    // GPS jitter used to cancel map tile downloads before they could paint.
    if (last != null &&
        (movedKm < .05 || elapsed < const Duration(seconds: 10))) {
      return;
    }

    driverLastCameraPoint = point;
    driverLastCameraAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([point, target]),
            padding: const EdgeInsets.fromLTRB(46, 118, 46, 330),
          ),
        );
      } catch (_) {
        // El siguiente evento GPS volverá a centrar la ruta.
      }
    });
  }

  Future<void> _hydrateDriverRideAddresses(
    Map<String, dynamic> ride,
  ) async {
    final rideId = ride['id']?.toString() ?? identityHashCode(ride).toString();
    if (driverAddressHydrationInFlight.contains(rideId)) return;

    if (!_isExpressPlaceholderAddress(ride['pickup_address']) &&
        !_isExpressPlaceholderAddress(ride['destination_address'])) return;

    driverAddressHydrationInFlight.add(rideId);
    try {
      final changed = await resolveExpressRouteAddressLabels(ride);
      if (mounted && changed) {
        setState(() {});
      }
    } finally {
      driverAddressHydrationInFlight.remove(rideId);
    }
  }

  Future<void> _openTripInWaze(Map<String, dynamic> trip) async {
    final target = _driverTripTarget(trip);
    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este viaje todavía no tiene coordenadas de navegación.'),
        ),
      );
      return;
    }

    final latLng = '${target.latitude},${target.longitude}';
    final appUri = Uri.parse('waze://?ll=$latLng&navigate=yes');
    final webUri = Uri.https(
      'waze.com',
      '/ul',
      {'ll': latLng, 'navigate': 'yes'},
    );

    try {
      if (await canLaunchUrl(appUri)) {
        final opened = await launchUrl(
          appUri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) return;
      }
      final opened = await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir Waze.')),
    );
  }

  Future<bool> _confirmTripCompletion(Map<String, dynamic> trip) async {
    final isParcel = _expressIsParcelTrip(trip);
    final rawRide = trip['ride_requests'];
    final ride = rawRide is Map
        ? Map<String, dynamic>.from(rawRide)
        : <String, dynamic>{};
    final fare = asDouble(trip['final_fare']) ??
        asDouble(ride['proposed_fare']) ??
        0;
    final currency =
        ride['currency']?.toString() ?? trip['currency']?.toString() ?? 'BOB';
    final fareLabel = _rideMoney(fare, currency);
    final payment = ride['payment_method']?.toString() ?? 'cash';
    final isCash = payment == 'cash';
    final isDriverQr = payment == 'driver_qr';

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => ExpressJourneyDialog(
            icon: isCash ? Icons.payments_rounded
                : isDriverQr ? Icons.qr_code_rounded
                : Icons.task_alt_rounded,
            title: isParcel
                ? (isCash ? 'Confirmar entrega y cobro'
                    : 'Confirmar entrega del paquete')
                : (isCash ? 'Confirmar cobro del viaje'
                    : isDriverQr ? 'Confirmar pago por QR'
                    : '¿Finalizar este viaje?'),
            subtitle: isParcel
                ? 'Verifica que entregaste el paquete al destinatario '
                    'antes de completar el servicio.'
                : 'Asegúrate de que el pasajero llegó a su destino '
                    'antes de marcar el viaje como completado.',
            content: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0B57D0).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF0B57D0).withValues(alpha: .14),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    isCash ? 'MONTO A COBRAR EN EFECTIVO'
                        : isDriverQr ? 'MONTO RECIBIDO POR QR'
                        : isParcel ? 'IMPORTE DEL ENVÍO' : 'IMPORTE DEL VIAJE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      fareLabel,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(dialogContext).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isCash
                        ? 'Verifica que recibiste el efectivo antes de continuar.'
                        : isDriverQr
                            ? 'Comprueba la transferencia en tu cuenta.'
                            : 'Medio de pago: ${_paymentLabel(payment)}.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.check_circle_rounded),
                label: Text(isParcel
                     ? (isCash ? 'Entregado y cobrado' : 'Marcar entregado')
                     : (isCash ? 'Ya cobré · Finalizar' : 'Finalizar viaje')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(isParcel ? 'Volver a la entrega' : 'Volver al viaje'),
              ),
            ],
          ),
        ) ??
        false;
  }

  bool get _driverFocusLocked => shouldLockDriverNavigation(
        incomingOffer: driverRequestPopupId != null ||
            driverDeliveryPopupId != null,
        waitingPassenger: driverOfferPendingRideId != null,
        processingTransition: driverRideActionBusy,
        hasActiveTrip: cachedData?.activeTrip != null,
        hasActiveDelivery: cachedData?.activeDelivery != null,
      );

  void _syncDriverFocusNavigation() {
    final locked = _driverFocusLocked;
    if (lastReportedDriverFocusLocked == locked) return;
    lastReportedDriverFocusLocked = locked;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Read current state here: a backend response may arrive between
        // scheduling this callback and the next frame.
        widget.onOfferPendingChanged?.call(_driverFocusLocked);
      }
    });
  }

  void _clearDriverOfferWait({bool refresh = false}) {
    driverOfferPendingTimer?.cancel();
    driverOfferPendingTimer = null;
    final changed =
        driverOfferPendingRideId != null || driverOfferPendingRemaining != 0;

    if (mounted && changed) {
      setState(() {
        driverOfferPendingRideId = null;
        driverOfferPendingRemaining = 0;
        driverOfferPendingExpiresAt = null;
      });
    } else {
      driverOfferPendingRideId = null;
      driverOfferPendingRemaining = 0;
      driverOfferPendingExpiresAt = null;
    }

    _syncDriverFocusNavigation();
    if (refresh && mounted) _refreshDriverHome();
  }

  void _startDriverOfferWait(
    Map<String, dynamic> offer,
    String rideRequestId,
  ) {
    if (!mounted) return;
    _closeDriverRequestPopup(showNext: false);

    final now = DateTime.now().toUtc();
    final expiresAt =
        DateTime.tryParse(offer['expires_at']?.toString() ?? '')?.toUtc() ??
            now.add(const Duration(seconds: 30));
    final remaining = math.max(
      1,
      (expiresAt.difference(now).inMilliseconds + 999) ~/ 1000,
    ).toInt();

    driverOfferPendingTimer?.cancel();
    setState(() {
      driverOfferPendingRideId = rideRequestId;
      driverOfferPendingExpiresAt = expiresAt;
      driverOfferPendingRemaining = remaining;
    });
    _syncDriverFocusNavigation();

    driverOfferPendingTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || driverOfferPendingRideId != rideRequestId) {
        timer.cancel();
        return;
      }

      final deadline = driverOfferPendingExpiresAt ?? expiresAt;
      final next = math.max(
        0,
        (deadline.difference(DateTime.now().toUtc()).inMilliseconds + 999) ~/
            1000,
      ).toInt();

      if (next <= 0) {
        timer.cancel();
        _clearDriverOfferWait(refresh: true);
        return;
      }

      if (next != driverOfferPendingRemaining) {
        setState(() => driverOfferPendingRemaining = next);
      }
    });
  }

  @override
  void initState() {
    ExpressConnectivityMonitor.instance.probe =
        () => _expressConnectivityProbe(widget.service);
    ExpressConnectivityMonitor.instance.addListener(_onConnectivityChanged);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ExpressCallPresence.start(widget.service);
      unawaited(syncDriverPushOverlayState(widget.service));
      unawaited(syncOverlayCallPreference(widget.service).then((granted) {
        if (mounted) setState(() => overlayAllowed = granted);
      }));
      // La sugerencia de sobreposición aparece al empezar un viaje, no al abrir la app.
    });
    WidgetsBinding.instance.addObserver(this);
    // Never replay an action received while this driver screen was unmounted.
    driverFloatingOfferFocus.value = null;
    driverFloatingOfferFocus.addListener(_onFloatingOfferFocus);
    // Un toque en el aviso puede montar esta pantalla (arranque en frío o
    // cambio de pasajero a conductor) antes de que exista el listener. Ese
    // único toque pendiente se conserva; se revalida al cargar los datos.
    final pendingNotificationOffer = driverNotificationOfferFocus.value;
    driverNotificationOfferFocus.value = null;
    driverNotificationOfferFocus.addListener(_onNotificationOfferFocus);
    if (pendingNotificationOffer != null) {
      _pendingFloatingFocusId = pendingNotificationOffer;
      _pendingFloatingFocusAt = DateTime.now().toUtc();
      _pendingFocusFromNotification = true;
    }
    unawaited(_loadFloatingOfferAdminFlag());
    driverFuture = _load();
    unawaited(_restoreNativeFloatingOfferOpen());
    _locate();
    unawaited(_refreshDriverMapContext());
    driverHeatTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (!mounted) return;
      if (cachedData?.profile['online_status'] == 'online') {
        unawaited(_refreshDriverMapContext());
      }
    });

    driverForegroundPushSubscription =
        expressForegroundPushEvents().listen((type) {
      if (!mounted) return;
      if (type == 'ride_request') {
        if (driverOfferPendingRideId == null &&
            driverDeliveryPopupId == null) _refreshDriverHome();
        return;
      }
      if (type == 'ride_offer_declined') {
        _clearDriverOfferWait(refresh: true);
        return;
      }
      if (type == 'ride_assigned' ||
          type == 'trip_status' ||
          type == 'passenger_on_way' ||
          type == 'trip_cancelled') {
        if (cachedData?.activeTrip != null) {
          _reconcileDriverHomeInBackground();
        } else {
          _refreshDriverHome();
        }
      }
    });

    // La recepción de solicitudes no puede depender únicamente de FCM.
    // Realtime despierta la pantalla ante INSERT/UPDATE de ride_requests.
    driverRideRequestsChannel = supabase
        .channel('driver-ride-requests-${widget.service.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_requests',
          callback: (payload) {
            // Cierre reactivo: cancellation / driver_selected / expiración.
            // Una barra de otra solicitud nunca se toca.
            final updated = payload.newRecord;
            final updatedStatus = updated['status']?.toString();
            final changedId =
                (updated.isNotEmpty ? updated : payload.oldRecord)['id']
                    ?.toString();
            final removed = payload.newRecord.isEmpty &&
                payload.oldRecord.isNotEmpty;
            final invalidated = changedId != null &&
                (removed ||
                    (updatedStatus != null &&
                        updatedStatus != 'searching' &&
                        updatedStatus != 'offers_received'));
            if (invalidated) {
              // Un evento de otra zona no debe disparar lecturas innecesarias.
              // La barra nativa solo se cierra si coincide el ID.
              unawaited(_floatingOffers.invalidateOffer(changedId));
              final isOpen = driverRequestPopupId == changedId;
              final isCached = cachedData?.rides.any(
                (ride) => ride['id']?.toString() == changedId,
              ) ?? false;
              if (isOpen || isCached) {
                if (isOpen) _closeDriverRequestPopup(showNext: false);
                _dropUnavailableRide(changedId);
                if (mounted) _refreshDriverHome();
                return;
              }
            }
            if (!expressDriverRealtimeShouldRefresh(
              record: payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord,
              zoneId: cachedData?.profile['zone_id']?.toString(),
              channel: ExpressRuntimeChannel.name,
            )) return;
            if (!mounted || busy || driverRequestPopupId != null) return;
            _refreshDriverHome();
          },
        )
        .subscribe();

    driverDeliveriesChannel = supabase
        .channel('driver-deliveries-${widget.service.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'delivery_requests',
          callback: (payload) {
            if (!expressDriverRealtimeShouldRefresh(
              record: payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord,
              zoneId: cachedData?.profile['zone_id']?.toString(),
              channel: ExpressRuntimeChannel.name,
            )) return;
            if (!mounted || busy || driverDeliveryPopupId != null ||
                driverRequestPopupId != null) return;
            _refreshDriverHome();
          },
        )
        .subscribe();

    driverNotificationsChannel = supabase
        .channel('driver-notifications-${widget.service.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.service.userId,
          ),
          callback: (payload) {
            if (!mounted || busy || driverRequestPopupId != null) return;
            if (payload.newRecord['type']?.toString() == 'ride_request') {
              _refreshDriverHome();
            }
          },
        )
        .subscribe();

    // Si el administrador cambia disponibilidad/visibilidad por zona, el modo
    // conductor también se refresca de inmediato para retirar solicitudes de
    // servicios deshabilitados sin esperar el polling de respaldo.
    driverZoneServicesChannel = supabase
        .channel('driver-zone-services-${widget.service.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'zone_service_catalog',
          callback: (payload) {
            if (!expressDriverRealtimeShouldRefresh(
              record: payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord,
              zoneId: cachedData?.profile['zone_id']?.toString(),
              channel: ExpressRuntimeChannel.name,
            )) return;
            if (!mounted || busy || driverRequestPopupId != null) return;
            _refreshDriverHome();
          },
        )
        .subscribe();

    // Respaldo de red: si push o Realtime se interrumpen, el conductor
    // consulta solicitudes disponibles sin depender del foco de Android.
    timer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted || busy || driverRequestPopupId != null) return;
      _refreshDriverHome();
    });
    // Lightweight backup while the native bar or popup is visible.
    _driverFloatingBarValidityTimer =
        Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_checkActiveDriverFloatingBar());
      unawaited(_checkDriverPopupValidity());
    });
  }

  @override
  void didUpdateWidget(covariant DriverMapHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      if (cachedData?.activeTrip != null) {
        _reconcileDriverHomeInBackground();
      } else {
        _refreshDriverHome();
      }
    }
  }

  void _refreshDriverHome() {
    if (!mounted || driverRefreshInFlight) return;
    driverRefreshInFlight = true;
    final nextFuture = _load().then((value) {
      ExpressConnectivityMonitor.instance.recordSuccess('driver_home');
      return value;
    }, onError: (Object error, StackTrace stack) {
      ExpressConnectivityMonitor.instance.recordFailure(error);
      // Never replace a working conductor screen with an error state during
      // a temporary HTTP abort. Preserve the last server-authorized view;
      // the existing 12-second retry/realtime subscriptions will refresh it.
      final previous = cachedData;
      if (previous != null) {
        unawaited(AppErrorReporter.capture(
          error, stack,
          source: 'driver_refresh',
          screen: 'driver_home',
          eventName: 'DRIVER_REFRESH_STALE_DATA_PRESERVED',
          fatal: false,
        ));
        return previous;
      }
      Error.throwWithStackTrace(error, stack);
    }).whenComplete(() {
      driverRefreshInFlight = false;
    });
    setState(() {
      driverFuture = nextFuture;
    });
  }

  // Después de una acción confirmada conservamos inmediatamente el estado
  // optimista visible. La lectura completa se hace en segundo plano y solo
  // reemplaza la UI cuando ya terminó, evitando un segundo estado de carga.
  void _reconcileDriverHomeInBackground() {
    unawaited(() async {
      try {
        final next = await _load();
        if (!mounted) return;
        driverFuture = Future.value(next);
        setState(() {});
      } catch (error, stack) {
        unawaited(
          AppErrorReporter.capture(
            error,
            stack,
            source: 'driver_background_reconcile',
            screen: 'driver_home',
            eventName: 'DRIVER_BACKGROUND_RECONCILE_FAILED',
          ),
        );
      }
    }());
  }

  Future<void> _locate({bool recenter = false}) async {
    try {
      final position = await locationService.currentPosition();
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      current = point;
      driverMapHeading.update(point, reportedDegrees: kIsWeb ? null : position.heading,
          speedMps: kIsWeb ? null : position.speed);
      driverPosition.value = point;
      // Keep a close driver camera on reload; recenter resets the zoom.
      if (recenter) driverMapZoom = 15.2;
      _centerDriverMap(point, driverMapZoom);
    } catch (_) {}
  }

  void _followDriverWhenIdle(LatLng point) {
    if (!driverFollowLocation || cachedData?.activeTrip != null ||
        cachedData?.activeDelivery != null || driverRequestPopupId != null) return;
    final now = DateTime.now();
    final elapsed = driverLastCameraAt == null ? const Duration(minutes: 1)
        : now.difference(driverLastCameraAt!);
    final previous = driverLastCameraPoint;
    final distance = previous == null ? double.infinity :
        locationService.distanceMeters(
          fromLatitude: previous.latitude,
          fromLongitude: previous.longitude,
          toLatitude: point.latitude,
          toLongitude: point.longitude,
        );
    if (distance < 12 && elapsed < const Duration(seconds: 12)) return;
    if (elapsed < const Duration(seconds: 2)) return;
    driverLastCameraPoint = point;
    driverLastCameraAt = now;
    _centerDriverMap(point, driverMapZoom);
  }

  void _startTracking({required bool highFrequency}) {
    if (positionSubscription != null &&
        driverTrackingHighFrequency == highFrequency) {
      return;
    }

    if (positionSubscription != null) {
      unawaited(positionSubscription?.cancel());
      positionSubscription = null;
    }
    driverTrackingHighFrequency = highFrequency;

    positionSubscription =
        locationService.positionStream(
          highFrequency: highFrequency, driverBackgroundTracking: true,
        ).listen(
      (position) async {
        final point = LatLng(position.latitude, position.longitude);
        current = point;

        final heading = driverMapHeading.update(
          point, reportedDegrees: kIsWeb ? null : position.heading,
          speedMps: kIsWeb ? null : position.speed,
        );

        if (mounted) {
          driverPosition.value = point;
          _followDriverWhenIdle(point);
          if (cachedData?.activeTrip != null) {
            _followActiveDriverTrip(point);
            setState(() {});
          }
        }

        // The device GPS remains live for every emitted tracking point. Backend
        // writes are deduplicated by movement/heading plus a heartbeat so the
        // passenger still sees a fluid route without unnecessary RPC traffic.
        final now = DateTime.now().toUtc();
        final hasActiveService =
            cachedData?.activeTrip != null || cachedData?.activeDelivery != null;
        final minSyncInterval = hasActiveService
            ? const Duration(seconds: 3)
            : const Duration(seconds: 10);
        final maxHeartbeat = hasActiveService
            ? const Duration(seconds: 12)
            : const Duration(seconds: 30);
        final movementThresholdMeters = hasActiveService ? 5.0 : 20.0;
        final headingThresholdDegrees = hasActiveService ? 15.0 : 35.0;

        final elapsed = driverLastLocationSyncAt == null
            ? maxHeartbeat
            : now.difference(driverLastLocationSyncAt!);
        final movedMeters = driverLastSyncedPoint == null
            ? double.infinity
            : locationService.distanceMeters(
                fromLatitude: driverLastSyncedPoint!.latitude,
                fromLongitude: driverLastSyncedPoint!.longitude,
                toLatitude: point.latitude,
                toLongitude: point.longitude,
              );

        final previousHeading = driverLastSyncedHeading;
        final rawHeadingDelta = previousHeading == null
            ? 360.0
            : (heading - previousHeading).abs() % 360;
        final headingDelta = rawHeadingDelta > 180
            ? 360 - rawHeadingDelta
            : rawHeadingDelta;

        final meaningfulChange =
            movedMeters >= movementThresholdMeters ||
                headingDelta >= headingThresholdDegrees;
        final shouldSync = !driverLocationSyncInFlight &&
            (driverLastLocationSyncAt == null ||
                elapsed >= maxHeartbeat ||
                (elapsed >= minSyncInterval && meaningfulChange));

        if (shouldSync) {
          driverLocationSyncInFlight = true;
          try {
            await widget.service.updateDriverDetails(
              latitude: position.latitude,
              longitude: position.longitude,
              headingDegrees: heading,
            );
            driverLastLocationSyncAt = now;
            driverLastSyncedPoint = point;
            driverLastSyncedHeading = heading;
          } catch (_) {
            // El siguiente punto vuelve a intentar sin bloquear el mapa.
          } finally {
            driverLocationSyncInFlight = false;
          }
        }


      },
      onError: (_) {},
    );
  }

  Future<_DriverStateData> _load() async {
    await _loadDriverApprovedWork();
    final profile = await widget.service.myDriverProfile() ??
        await widget.service.ensureDriverProfile();
    try {
      final vehicles = await widget.service.myVehicles();
      final activeVehicles = vehicles.where((v) => v['is_active'] == true).toList()
        ..sort((a, b) => (b['updated_at'] ?? b['created_at'] ?? '').toString()
            .compareTo((a['updated_at'] ?? a['created_at'] ?? '').toString()));
      driverMapVehicleType = expressMapVehicleType(
        activeVehicles.isEmpty ? null : activeVehicles.first['vehicle_type'],
        summary: profile['vehicle_summary']?.toString(),
      );
    } catch (_) {
      // Keep last scoped vehicle on transient failures. Never infer type by city.
    }


    final driverNow = DateTime.now().toUtc();
    final priorityStale = driverPriorityLoadedAt == null ||
        driverNow.difference(driverPriorityLoadedAt!) >
            const Duration(minutes: 1);
    if (priorityStale) {
      try {
        driverPrioritySummary =
            await widget.service.myDriverPrioritySummary();
        driverPriorityEnforced =
            driverPrioritySummary['enabled'] == true &&
            driverPrioritySummary['enforcement_enabled'] == true;
      } catch (_) {
        driverPrioritySummary = const {};
        driverPriorityEnforced = false;
      } finally {
        // También aplicamos backoff ante un fallo temporal para no martillar
        // el endpoint en cada refresco de respaldo.
        driverPriorityLoadedAt = driverNow;
      }
    }
    final trips = await widget.service.myTrips();
    final mineDeliveries = await widget.service.myDeliveries();

    Map<String, dynamic>? activeTrip;
    for (final row in trips) {
      if (row['driver_id'] == widget.service.userId) {
        final status = row['status']?.toString();
        if (status != 'completed' && status != 'cancelled') {
          activeTrip = row;
          break;
        }
      }
    }

    if (activeTrip != null) {
      final rawActiveRide = activeTrip['ride_requests'];
      if (rawActiveRide is Map) {
        final mutableRide = Map<String, dynamic>.from(rawActiveRide);
        activeTrip = <String, dynamic>{
          ...activeTrip,
          'ride_requests': mutableRide,
        };
        unawaited(_hydrateDriverRideAddresses(mutableRide));
      }

      if (driverOfferPendingRideId != null) {
        driverOfferPendingTimer?.cancel();
        driverOfferPendingTimer = null;
        driverOfferPendingRideId = null;
        driverOfferPendingRemaining = 0;
        _syncDriverFocusNavigation();
      }

      if (activeTrip['status']?.toString() == 'driver_waiting') {
        try {
          final history =
              await widget.service.tripHistory(activeTrip['id'].toString());
          String? waitingSince;
          String? passengerOnWayAt;
          for (final event in history) {
            final eventStatus = event['status']?.toString();
            final createdAt = event['created_at']?.toString();
            if (eventStatus == 'driver_waiting' && createdAt != null) {
              waitingSince = createdAt;
            } else if (eventStatus == 'passenger_on_way' &&
                createdAt != null) {
              passengerOnWayAt = createdAt;
            }
          }
          activeTrip = <String, dynamic>{
            ...activeTrip,
            'driver_waiting_since': waitingSince,
            'passenger_on_way_at': passengerOnWayAt,
          };
        } catch (_) {
          // El viaje sigue siendo utilizable aunque el historial tarde.
        }
      }
    }

    Map<String, dynamic>? activeDelivery;
    for (final row in mineDeliveries) {
      if (row['courier_id'] == widget.service.userId) {
        final status = row['status']?.toString();
        if (status != 'delivered' && status != 'cancelled') {
          activeDelivery = row;
          break;
        }
      }
    }

    if (activeDelivery != null &&
        driverOfferPendingRideId?.startsWith('delivery:') == true) {
      _clearDriverOfferWait();
    }

    final driverStatus = profile['online_status']?.toString();
    final hasActiveDriverService =
        activeTrip != null || activeDelivery != null;
    final shouldTrackDriverLocation =
        profile['approval_status'] == 'approved' &&
        (hasActiveDriverService ||
            driverStatus == 'online' ||
            driverStatus == 'busy');

    // El tracking pertenece exclusivamente al runtime del conductor. Se
    // reactiva al reconstruir la app si hay un servicio activo y se corta
    // también cuando el backend deja al conductor fuera de línea.
    if (shouldTrackDriverLocation) {
      _startTracking(highFrequency: hasActiveDriverService);
    } else if (positionSubscription != null) {
      await positionSubscription?.cancel();
      positionSubscription = null;
      driverTrackingHighFrequency = null;
      driverLastLocationSyncAt = null;
      driverLastSyncedPoint = null;
      driverLastSyncedHeading = null;
      driverLocationSyncInFlight = false;
    }

    List<Map<String, dynamic>> rides = [];
    List<Map<String, dynamic>> deliveries = [];
    if (profile['approval_status'] == 'approved' &&
        profile['online_status'] == 'online' &&
        activeTrip == null &&
        activeDelivery == null) {
      if (driverApprovedWorkKeys.contains('ride') ||
          driverApprovedWorkKeys.contains('parcel')) {
        final available = await widget.service.availableRideRequests();
        rides = available.where((job) {
          final key = job['service_mode'] == 'parcel' ? 'parcel' : 'ride';
          return driverApprovedWorkKeys.contains(key);
        }).toList();
      }
      if (driverApprovedWorkKeys.contains('parcel') ||
          driverApprovedWorkKeys.contains('market')) {
        final offered = await widget.service.availableDeliveries();
        deliveries = offered
            .where((d) =>
                expressPrimaryDriverMayReceiveDelivery(d, driverApprovedWorkKeys))
            .toList();
      }
      // Con prioridad activa el backend ya entrega las solicitudes ordenadas
      // según nivel, cercanía, reputación del pasajero y valor relativo.
      // Cuando el filtro está apagado conservamos el comportamiento anterior.
      if (!driverPriorityEnforced) {
        rides.sort((a, b) {
          final aDistance = _pickupDistanceKm(
                current,
                asDouble(a['pickup_latitude']),
                asDouble(a['pickup_longitude']),
              ) ??
              double.infinity;
          final bDistance = _pickupDistanceKm(
                current,
                asDouble(b['pickup_latitude']),
                asDouble(b['pickup_longitude']),
              ) ??
              double.infinity;
          final distanceCompare = aDistance.compareTo(bDistance);
          if (distanceCompare != 0) return distanceCompare;

          final aCreated =
              DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);
          final bCreated =
              DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);
          return aCreated.compareTo(bCreated);
        });
      }
      if (!viewedRideRequestIdsLoaded) {
        try {
          final serverViewedIds =
              await widget.service.myViewedRideRequestIds();
          viewedRideRequestIds.addAll(serverViewedIds);
          viewedRideRequestIdsLoaded = true;
        } catch (_) {}
      }
    }

    Map<String, dynamic>? counterpart;
    final counterpartId = activeTrip?['passenger_id']?.toString() ??
        activeDelivery?['customer_id']?.toString();
    if (counterpartId != null) {
      counterpart = await widget.service.userById(counterpartId);
    }

    Map<String, dynamic>? pendingRating = cachedData?.pendingRating;
    final pendingRatingNow = DateTime.now().toUtc();
    final pendingRatingStale = driverPendingRatingLoadedAt == null ||
        pendingRatingNow.difference(driverPendingRatingLoadedAt!) >
            const Duration(seconds: 30);
    if (pendingRatingStale) {
      pendingRating = await widget.service.pendingRatingService();
      driverPendingRatingLoadedAt = pendingRatingNow;
    }

    final next = _DriverStateData(
      service: widget.service,
      profile: profile,
      rides: rides,
      deliveries: deliveries,
      activeTrip: activeTrip,
      activeDelivery: activeDelivery,
      counterpart: counterpart,
      pendingRating: pendingRating,
    );
    cachedData = next;
    _maybePromptOverlayOnDriverTrip(next.activeTrip);
    if (_pendingFloatingFocusId != null && _appInForeground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumePendingFloatingFocus();
      });
    }
    // Realtime and fallback polling both update _load(): resync existing
    // native card on new/expired/cancelled requests even when backgrounded.
    if (!_appInForeground) unawaited(_syncFloatingOffer());
    unawaited(_loadFloatingOfferAdminFlag());
    _syncDriverFocusNavigation();
    _observeDriverTripTransition(next);
    final requestCount = next.rides.length + next.deliveries.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onRequestCountChanged?.call(requestCount);
      }
    });
    _syncDriverRequestPopup(next);
    return next;
  }

  void _observeDriverTripTransition(_DriverStateData data) {
    final trip = data.activeTrip;
    final tripId = trip?['id']?.toString();
    final status = trip?['status']?.toString();
    if (tripId == null || status == null) return;

    if (lastAnimatedDriverTripId == tripId &&
        lastAnimatedDriverTripStatus == status) {
      return;
    }

    final previous = lastAnimatedDriverTripStatus;
    lastAnimatedDriverTripId = tripId;
    lastAnimatedDriverTripStatus = status;

    // La asignación es un cambio remoto para el conductor: la destacamos
    // aunque sea el primer estado del nuevo viaje.
    if (status != 'driver_assigned' && previous == null) return;

    final isParcel = _expressIsParcelTrip(trip!);
    String? title;
    String? subtitle;
    switch (status) {
      case 'driver_assigned':
        title = isParcel ? '¡Envío confirmado!' : '¡Viaje confirmado!';
        subtitle = isParcel
            ? 'Recoge el paquete del remitente y llévalo al destinatario.'
            : 'Tu oferta fue aceptada. Dirígete al punto de recogida.';
        break;
      case 'emergency':
        title = 'Alerta de emergencia';
        subtitle = 'El viaje cambió a estado de emergencia.';
        break;
    }
    if (title == null || subtitle == null) return;
    unawaited(HapticFeedback.selectionClick());
    unawaited(
      AppErrorReporter.event(
        'DRIVER_TRIP_STATE_' + status.toUpperCase(),
        source: 'ride_state_change',
        screen: 'driver_home',
        context: {'status': status},
      ),
    );
  }

  Future<void> _ratePending(Map<String, dynamic> pending) async {
    final saved = await showExpressRatingDialog(
      context,
      widget.service,
      pending,
      counterpartLabel: pending['service_mode'] == 'parcel'
          ? 'cliente del envío' : 'pasajero',
    );
    if (saved && mounted) {
      final current = cachedData;
      if (current != null) {
        final cleared = _DriverStateData(
          service: current.service,
          profile: current.profile,
          rides: current.rides,
          deliveries: current.deliveries,
          activeTrip: current.activeTrip,
          activeDelivery: current.activeDelivery,
          counterpart: current.counterpart,
          pendingRating: null,
        );
        cachedData = cleared;
        driverFuture = Future.value(cleared);
        setState(() {});
      }
      _reconcileDriverHomeInBackground();
      widget.onChanged();
    }
  }

  Future<void> _toggleOnline(Map<String, dynamic> profile) async {
    if (busy) return;

    final state = cachedData;
    final hasActiveService =
        state?.activeTrip != null || state?.activeDelivery != null;
    if (hasActiveService) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No puedes ponerte en línea mientras tienes un servicio activo. '
              'Finaliza el viaje o delivery primero.',
            ),
          ),
        );
      return;
    }

    final wasOnline = profile['online_status'] == 'online';
    setState(() => busy = true);

    try {
      if (wasOnline) {
        await widget.service.setDriverOnline(false);
        await positionSubscription?.cancel();
        positionSubscription = null;
      } else {
        // Compuerta de registro: documentos/vehículo siempre según onboarding.
        // La suscripción solo bloquea si la zona tiene enforce_access=true.
        final List<String> missing;
        try {
          missing = await driverRegistrationMissing(widget.service);
        } catch (_) {
          if (mounted) {
            setState(() => busy = false);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('No pudimos verificar tu registro. Intenta nuevamente.'),
                ),
              );
          }
          return;
        }
        if (missing.isNotEmpty) {
          if (!mounted) return;
          setState(() => busy = false);
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Completa tu registro'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Para conectarte completa los requisitos pendientes:',
                  ),
                  const SizedBox(height: 10),
                  for (final item in missing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $item'),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
          return;
        }

        // Al conectar, renovamos/registramos el token FCM en segundo plano.
        // Así un token que Firebase haya marcado inválido no deja al conductor
        // sin alertas hasta el próximo reinicio de la app.
        final accessToken = supabase.auth.currentSession?.accessToken;
        if (accessToken != null && accessToken.isNotEmpty) {
          unawaited(enablePushNotifications(accessToken));
        }

        // Never enable dispatch before the server has committed the fresh
        // GPS fix. Future.wait caused the online trigger to see stale
        // coordinates and reject valid Iquique drivers (P0001).
        final position = await locationService.currentPosition(
          allowCachedFallback: false,
        );
        if (!locationService.isUsablePosition(
          position,
          maxAccuracyMeters: 180,
          allowMocked: expressPreviewDemandMode,
        )) {
          throw StateError(
            'No se pudo validar un GPS reciente y preciso. '
            'Activa la ubicación precisa e inténtalo nuevamente.',
          );
        }
        final point = LatLng(position.latitude, position.longitude);
        await saveDriverGpsThenConnect(
          savePosition: () => widget.service.updateDriverDetails(
            latitude: position.latitude,
            longitude: position.longitude,
            headingDegrees: position.heading.isFinite &&
                    position.heading >= 0 &&
                    position.heading <= 360
                ? position.heading
                : null,
          ),
          setOnline: () => widget.service.setDriverOnline(true),
        );
        current = point;
        driverMapHeading.update(point, reportedDegrees: kIsWeb ? null : position.heading,
          speedMps: kIsWeb ? null : position.speed);
        driverPosition.value = point;
        // Al ponerse online todavía no hay servicio activo: usamos el nivel
        // reducido hasta que _load detecte un viaje/delivery y eleve tracking.
        _startTracking(highFrequency: false);
      }

      if (!mounted) return;
      // Reflejo optimista inmediato: el conductor ve el cambio en cuanto el
      // backend confirma, sin esperar otra lectura completa de perfil.
      profile['online_status'] = wasOnline ? 'offline' : 'online';
      setState(() => busy = false);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      final rawMessage = e is PostgrestException
          ? e.message.trim()
          : e.toString().replaceFirst('Bad state: ', '').trim();
      final normalized = rawMessage.toLowerCase();
      final String displayMessage;
      if (normalized.contains('no coincide con tu zona')) {
        displayMessage = 'Tu GPS actual no coincide con tu zona registrada. '
            'Comprueba tu zona en Perfil y vuelve a intentarlo dentro '
            'de su cobertura.';
      } else if (normalized.contains('todavía no está disponible') ||
          normalized.contains('todavia no esta disponible')) {
        displayMessage = 'Express todavía no está disponible para '
            'conductores en esta ubicación.';
      } else if (normalized.contains('activa el gps') ||
          normalized.contains('ubicación') ||
          normalized.contains('ubicacion') ||
          normalized.contains('señal gps') ||
          normalized.contains('gps reciente')) {
        displayMessage = 'No fue posible validar tu GPS. '
            'Activa la ubicación precisa y vuelve a intentarlo.';
      } else if (normalized.contains('suscripci')) {
        displayMessage = 'Necesitas una suscripción activa '
            'para conectarte en esta zona.';
      } else {
        displayMessage = 'No pudimos conectarte. '
            'Inténtalo nuevamente; si persiste, contacta con soporte.';
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(displayMessage)));
    }
  }

  Future<void> _offerRide(Map<String, dynamic> ride) async {
    final input = await showDialog<DriverOfferInput>(
      context: context,
      builder: (_) => DriverOfferDialog(
        title: 'Enviar oferta',
        fareLabel: 'Tu tarifa',
        initialFare: ride['proposed_fare']?.toString() ?? '',
        summary: Text(
          (isExpressPlaceholderAddress(ride['pickup_address'])
                  ? 'Resolviendo ubicación…'
                  : ride['pickup_address'].toString()) +
              ' → ' +
              (isExpressPlaceholderAddress(ride['destination_address'])
                  ? 'Resolviendo ubicación…'
                  : ride['destination_address'].toString()),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );

    if (input == null) return;
    final amount = num.tryParse(input.fareText.trim().replaceAll(',', '.'));
    final eta = int.tryParse(input.etaText.trim());

    if (amount == null || eta == null) return;

    try {
      final offer = await runExpressStateTransition<Map<String, dynamic>>(
        context,
        processingTitle: 'Enviando oferta…',
        processingSubtitle: 'El pasajero la verá en unos instantes.',
        successTitle: 'Oferta enviada',
        successSubtitle: 'Esperando confirmación del pasajero.',
        eventName: 'DRIVER_OFFER_SENT',
        action: () => widget.service.createRideOffer(
          rideRequestId: ride['id'].toString(),
          fare: amount,
          etaMinutes: eta,
          currencyCode: ride['currency']?.toString(),
        ),
      );
      if (!mounted) return;
      _startDriverOfferWait(offer, ride['id'].toString());
      _refreshDriverHome();
    } catch (e) {
      if (!mounted) return;
      final debtAction = await showCancellationDebtBlock(
        context,
        e,
        driver: true,
      );
      if (debtAction != null) {
        if (debtAction) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ExpressWalletPage(
                service: widget.service,
                driver: true,
              ),
            ),
          );
        }
        return;
      }
      if (isRideOfferUnavailableError(e)) {
        _closeDriverRequestPopup(showNext: false);
        _dropUnavailableRide(ride['id']?.toString() ?? '');
        unawaited(_syncFloatingOffer());
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyRideOfferError(e))),
      );
    }
  }

  Future<void> _quickOfferRide(
    Map<String, dynamic> ride,
    num amount,
  ) async {
    stopExpressAlertSound();
    final distanceKm = _pickupDistanceKm(
      current,
      asDouble(ride['pickup_latitude']),
      asDouble(ride['pickup_longitude']),
    );
    final eta =
        (((distanceKm ?? 1.5) * 3).ceil()).clamp(2, 30).toInt();

    try {
      final offer = await runExpressStateTransition<Map<String, dynamic>>(
        context,
        processingTitle: 'Enviando oferta…',
        processingSubtitle: 'Confirmando tu propuesta con Express.',
        successTitle: 'Oferta enviada',
        successSubtitle: 'Ahora esperamos la respuesta del pasajero.',
        eventName: 'DRIVER_QUICK_OFFER_SENT',
        action: () => widget.service.createRideOffer(
          rideRequestId: ride['id'].toString(),
          fare: amount,
          etaMinutes: eta,
          currencyCode: ride['currency']?.toString(),
        ),
      );
      if (!mounted) return;
      _startDriverOfferWait(offer, ride['id'].toString());
      _refreshDriverHome();
    } catch (e) {
      if (!mounted) return;
      final debtAction = await showCancellationDebtBlock(
        context,
        e,
        driver: true,
      );
      if (debtAction != null) {
        if (debtAction) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ExpressWalletPage(
                service: widget.service,
                driver: true,
              ),
            ),
          );
        }
        return;
      }
      if (isRideOfferUnavailableError(e)) {
        _closeDriverRequestPopup(showNext: false);
        _dropUnavailableRide(ride['id']?.toString() ?? '');
        unawaited(_syncFloatingOffer());
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyRideOfferError(e)),
        ),
      );
    }
  }

  /// Quita de la vista una solicitud que el servidor ya no considera disponible
  /// (vencida, tomada o cancelada). La lista se reconcilia en memoria; el
  /// siguiente refresco confirma el estado real del servidor.
  void _dropUnavailableRide(String rideId) {
    final current = cachedData;
    if (current == null || rideId.isEmpty) return;
    final rides = current.rides
        .where((ride) => ride['id']?.toString() != rideId)
        .toList();
    final next = _DriverStateData(
      service: current.service,
      profile: current.profile,
      rides: rides,
      deliveries: current.deliveries,
      activeTrip: current.activeTrip,
      activeDelivery: current.activeDelivery,
      counterpart: current.counterpart,
      pendingRating: current.pendingRating,
    );
    cachedData = next;
    driverFuture = Future.value(next);
    if (mounted) setState(() {});
  }

  Future<void> _acceptRideAtPassengerFare(
    Map<String, dynamic> ride,
  ) async {
    // Vencida según el servidor: no se intenta aceptar, se retira de la vista.
    if (isRideOfferExpiredAt(ride['expires_at'], DateTime.now().toUtc())) {
      _closeDriverRequestPopup();
      _dropUnavailableRide(ride['id']?.toString() ?? '');
      unawaited(_syncFloatingOffer());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyRideOfferError('Oferta vencida o no disponible'))),
      );
      return;
    }
    final amount = asDouble(ride['proposed_fare']);
    if (amount == null || amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La tarifa de esta solicitud no es válida.')),
      );
      return;
    }

    final distanceKm = _pickupDistanceKm(
      current,
      asDouble(ride['pickup_latitude']),
      asDouble(ride['pickup_longitude']),
    );
    final eta =
        (((distanceKm ?? 1.5) * 3).ceil()).clamp(2, 30).toInt();

    try {
      final offer = await runExpressStateTransition<Map<String, dynamic>>(
        context,
        processingTitle: 'Aceptando tarifa…',
        processingSubtitle: 'Enviando tu confirmación al pasajero.',
        successTitle: 'Tarifa aceptada',
        successSubtitle: 'Esperando que el pasajero confirme el viaje.',
        eventName: 'DRIVER_PASSENGER_FARE_ACCEPTED',
        action: () => widget.service.createRideOffer(
          rideRequestId: ride['id'].toString(),
          fare: amount,
          etaMinutes: eta,
          currencyCode: ride['currency']?.toString(),
        ),
      );
      if (!mounted) return;
      _startDriverOfferWait(offer, ride['id'].toString());
      _refreshDriverHome();
    } catch (e, stack) {
      if (!mounted) return;
      unawaited(AppErrorReporter.capture(e, stack,
          source: 'offer_accept', screen: 'driver_offer', eventName: 'OFFER_ACCEPT_FAILED'));
      final debtAction = await showCancellationDebtBlock(
        context,
        e,
        driver: true,
      );
      if (debtAction != null) {
        if (debtAction) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ExpressWalletPage(
                service: widget.service,
                driver: true,
              ),
            ),
          );
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyRideOfferError(e))),
      );
      if (isRideOfferUnavailableError(e)) {
        // Ya no está disponible: se retira popup, lista y tarjeta flotante.
        _closeDriverRequestPopup();
        _dropUnavailableRide(ride['id']?.toString() ?? '');
        unawaited(_syncFloatingOffer());
      }
    }
  }

  Future<void> _customDeliveryOffer(Map<String, dynamic> delivery) async {
    if (delivery['marketplace_order_id'] != null) return;
    final input = await showDialog<DriverOfferInput>(
      context: context,
      builder: (_) => DriverOfferDialog(
        title: 'Enviar oferta de envío',
        fareLabel: 'Tu tarifa',
        initialFare: delivery['proposed_fare']?.toString() ?? '',
      ),
    );
    if (input == null) return;
    final amount = num.tryParse(input.fareText.trim().replaceAll(',', '.'));
    final eta = int.tryParse(input.etaText.trim());
    if (amount == null || amount <= 0 ||
        eta == null || eta < 1 || eta > 120) return;
    await _submitDriverDeliveryOffer(delivery, amount, etaMinutes: eta);
  }

  Future<void> _submitDriverDeliveryOffer(
    Map<String, dynamic> delivery, num amount, {int? etaMinutes}
  ) async {
    if (amount <= 0 || busy || driverOfferPendingRideId != null) return;
    // Orders already paid in Marketplace cannot be repriced by a driver.
    if (delivery['marketplace_order_id'] != null) {
      if (amount == (asDouble(delivery['proposed_fare']) ?? -1)) {
        await _claimDelivery(delivery);
      }
      return;
    }
    final distance = _pickupDistanceKm(current,
      asDouble(delivery['pickup_latitude']),
      asDouble(delivery['pickup_longitude']));
    final eta = etaMinutes ??
        (((distance ?? 1.5) * 3).ceil()).clamp(2, 30).toInt();
    try {
      final offer = await runExpressStateTransition<Map<String, dynamic>>(
        context,
        processingTitle: 'Enviando oferta…',
        processingSubtitle: 'El cliente podrá aprobar tu tarifa.',
        successTitle: 'Oferta enviada',
        successSubtitle: 'Esperando la confirmación del cliente.',
        eventName: 'DRIVER_PARCEL_OFFER_SENT',
        action: () => widget.service.createDeliveryDriverOffer(
          deliveryId: delivery['id'].toString(), fare: amount,
          etaMinutes: eta,
        ),
      );
      if (!mounted) return;
      _closeDriverDeliveryPopup(showNext: false);
      _startDriverOfferWait(offer, 'delivery:' + delivery['id'].toString());
      _refreshDriverHome();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo enviar la oferta: $error'),
      ));
    }
  }

  Future<void> _claimDelivery(Map<String, dynamic> delivery) async {
    if (busy || driverOfferPendingRideId != null ||
        cachedData?.activeTrip != null || cachedData?.activeDelivery != null) return;
    setState(() => busy = true);
    if (driverDeliveryPopupId != null) {
      _closeDriverDeliveryPopup(showNext: false);
    }
    try {
      await widget.service.claimDelivery(delivery['id'].toString());
      if (!mounted) return;
      _refreshDriverHome();
      widget.onChanged();
    } catch (e, stack) {
      if (!mounted) return;
      unawaited(AppErrorReporter.capture(e, stack,
          source: 'delivery_accept', screen: 'driver_delivery', eventName: 'DELIVERY_ACCEPT_FAILED'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyRideOfferError(e))),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _openDeliveryTracking(Map<String, dynamic> delivery) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceTrackingPage(
          title: 'Ruta del delivery',
          status: delivery['status']?.toString() ?? '',
          driverId: widget.service.userId,
          pickupLatitude: asDouble(delivery['pickup_latitude']),
          pickupLongitude: asDouble(delivery['pickup_longitude']),
          destinationLatitude: asDouble(delivery['dropoff_latitude']),
          destinationLongitude: asDouble(delivery['dropoff_longitude']),
        ),
      ),
    );
  }

  String? _nextTripStatus(String? status) {
    switch (status) {
      case 'driver_assigned':
        return 'driver_waiting';
      case 'driver_arriving':
        return 'driver_waiting';
      case 'driver_waiting':
        return 'in_progress';
      case 'in_progress':
        return 'completed';
      default:
        return null;
    }
  }

  String? _nextDeliveryStatus(String? status) {
    switch (status) {
      case 'accepted':
        return 'picked_up';
      case 'picked_up':
        return 'in_transit';
      case 'in_transit':
        return 'delivered';
      default:
        return null;
    }
  }

  Future<void> _advanceTrip(Map<String, dynamic> trip) async {
    if (_expressOfflineBlocked(context)) return;
    if (driverRideActionBusy) return;
    final isParcel = _expressIsParcelTrip(trip);
    final next = _nextTripStatus(trip['status']?.toString());
    if (next == null) return;

    if (next == 'completed') {
      final confirmed = await _confirmTripCompletion(trip);
      if (!confirmed || !mounted) return;

      final previousData = cachedData;
      setState(() => driverRideActionBusy = true);
      try {
        await widget.service.advanceTrip(trip['id'].toString(), 'completed');
        if (!mounted) return;

        // Antes se conservaba hasta 30 s el pendingRating=null leído mientras
        // el viaje seguía activo. Al completar forzamos una lectura fresca para
        // que el conductor pueda calificar al pasajero inmediatamente.
        driverPendingRatingLoadedAt = null;
        final freshPendingRating =
            await widget.service.pendingRatingService();
        driverPendingRatingLoadedAt = DateTime.now().toUtc();

        if (previousData != null) {
          final optimistic = _DriverStateData(
            service: previousData.service,
            profile: previousData.profile,
            rides: previousData.rides,
            deliveries: previousData.deliveries,
            activeTrip: null,
            activeDelivery: previousData.activeDelivery,
            counterpart: previousData.counterpart,
            pendingRating: freshPendingRating,
          );
          cachedData = optimistic;
          driverFuture = Future.value(optimistic);
          setState(() {});
        }

        lastAnimatedDriverTripId = trip['id']?.toString();
        lastAnimatedDriverTripStatus = 'completed';
        _refreshDriverHome();
        widget.onChanged();

        if (freshPendingRating != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final currentPending = cachedData?.pendingRating;
            if (currentPending?['id']?.toString() !=
                freshPendingRating['id']?.toString()) {
              return;
            }
            unawaited(_ratePending(currentPending!));
          });
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo finalizar: ' + e.toString())),
        );
      } finally {
        if (mounted) setState(() => driverRideActionBusy = false);
      }
      return;
    }

    String? pin;
    if (next == 'in_progress') {
      if (isParcel) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmar recogida'),
            content: const Text(
              'Confirma únicamente cuando hayas recibido físicamente '
              'el paquete del remitente. Después irás al destinatario.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Volver')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Paquete recogido')),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      } else {
        pin = await _askBoardingPin();
        if (pin == null || !mounted) return;
      }
    }

    final processingTitle = switch (next) {
      'driver_arriving' => 'Preparando ruta…',
      'driver_waiting' => 'Confirmando llegada…',
      'in_progress' => 'Validando PIN…',
      _ => 'Actualizando viaje…',
    };
    final successTitle = switch (next) {
      'driver_arriving' => 'Ruta iniciada',
      'driver_waiting' => 'Llegada confirmada',
      'in_progress' => 'Viaje iniciado',
      _ => 'Estado actualizado',
    };
    final successSubtitle = switch (next) {
      'driver_arriving' => 'El pasajero ya sabe que vas en camino.',
      'driver_waiting' => 'Avisamos al pasajero que ya llegaste.',
      'in_progress' => 'PIN correcto. El viaje está en curso.',
      _ => 'El cambio quedó registrado.',
    };

    final parcelProcessing = isParcel && next == 'in_progress';

    // El estado del viaje solo cambia en pantalla cuando el servidor confirma
    // la transición (onSuccess). Mientras tanto se muestra el estado anterior
    // con el indicador de proceso: nunca se confirma un viaje sin respuesta.
    setState(() {
      driverRideActionBusy = true;
    });

    try {
      await runExpressStateTransition<void>(
        context,
        processingTitle: parcelProcessing ? 'Confirmando recogida…' : processingTitle,
        processingSubtitle: 'No cierres esta pantalla mientras confirmamos.',
        successTitle: parcelProcessing ? 'Paquete recogido' : successTitle,
        successSubtitle: parcelProcessing
            ? 'Ahora dirígete al destinatario.' : successSubtitle,
        eventName: 'DRIVER_TRIP_' + next.toUpperCase(),
        action: () async {
          if (next == 'in_progress') {
            if (isParcel) {
              await widget.service.confirmParcelPickup(trip['id'].toString());
            } else {
              await widget.service.startTripWithPin(
                tripId: trip['id'].toString(),
                pin: pin!,
              );
            }
          } else {
            await widget.service.advanceTrip(trip['id'].toString(), next);
          }
        },
        onSuccess: (_) {
          final currentData = cachedData;
          if (currentData?.activeTrip == null) return;
          final optimisticTrip =
              Map<String, dynamic>.from(currentData!.activeTrip!);
          optimisticTrip['status'] = next;
          final optimistic = _DriverStateData(
            service: currentData.service,
            profile: currentData.profile,
            rides: currentData.rides,
            deliveries: currentData.deliveries,
            activeTrip: optimisticTrip,
            activeDelivery: currentData.activeDelivery,
            counterpart: currentData.counterpart,
            pendingRating: currentData.pendingRating,
          );
          cachedData = optimistic;
          driverFuture = Future.value(optimistic);
          lastAnimatedDriverTripId = trip['id']?.toString();
          lastAnimatedDriverTripStatus = next;
          if (mounted) setState(() {});
        },
      );

      if (!mounted) return;
      lastAnimatedDriverTripId = trip['id']?.toString();
      lastAnimatedDriverTripStatus = next;
      _refreshDriverHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      // Releer el estado real del servidor: el fallo puede haber ocurrido
      // después de que el viaje cambiara.
      _refreshDriverHome();
      final message = e.toString().contains('PIN incorrecto')
          ? 'El PIN no coincide. Pídeselo nuevamente al pasajero.'
          : 'No se pudo avanzar: ' + e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => driverRideActionBusy = false);
    }
  }

  Future<String?> _askBoardingPin() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
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
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
          ),
          decoration: const InputDecoration(
            // Marcadores que no son dígitos: "0000" se leía como PIN ya escrito.
            hintText: '· · · ·',
            helperText: 'Pide al pasajero su PIN de 4 dígitos.',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final pin = controller.text.trim();
              if (pin.length == 4 && int.tryParse(pin) != null) {
                Navigator.pop(dialogContext, pin);
              }
            },
            child: const Text('Iniciar viaje'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _advanceDelivery(Map<String, dynamic> delivery) async {
    final next = _nextDeliveryStatus(delivery['status']?.toString());
    if (next == null) return;
    try {
      await widget.service.advanceDelivery(delivery['id'].toString(), next);
      if (!mounted) return;
      _refreshDriverHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo avanzar: ' + e.toString())),
      );
    }
  }

  Future<void> _cancelDriverTrip(Map<String, dynamic> trip) async {
    final reason = await askExpressCancellationReason(context, 'viaje');
    if (reason == null || !mounted) return;
    final tripId = trip['id'].toString();
    final confirmedFee = await confirmTripCancellationFee(
      context,
      widget.service,
      tripId,
    );
    if (confirmedFee == null || !mounted) return;
    try {
      await widget.service.cancelTrip(
        tripId,
        reason: reason,
        confirmedFee: confirmedFee,
      );
      if (!mounted) return;
      _refreshDriverHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: ' + e.toString())),
      );
    }
  }

  Future<void> _cancelDriverDelivery(Map<String, dynamic> delivery) async {
    final reason = await askExpressCancellationReason(context, 'delivery');
    if (reason == null || !mounted) return;
    try {
      await widget.service.cancelDelivery(
        delivery['id'].toString(),
        reason: reason,
      );
      if (!mounted) return;
      _refreshDriverHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: ' + e.toString())),
      );
    }
  }

  /// Driver-only opt-in, never displayed to a passenger.
  Future<void> _showFloatingOfferSettings() async {
    final adminOn = await _loadFloatingOfferAdminFlag(force: true);
    final adminUnavailable = _floatingAdminUnavailable;
    var enabled = await _floatingOffers.settings.isEnabled();
    var permissionGranted = await _floatingOffers.bridge.hasPermission();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Ventana flotante'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Puede mostrar la burbuja sobre otras aplicaciones cuando '
                  'Express está en segundo plano. Es opcional y depende de los '
                  'permisos del teléfono. Puedes desactivarla cuando quieras.'),
              const SizedBox(height: 12),
              if (!adminOn)
                Text(adminUnavailable
                    ? 'No pudimos verificar esta función. Revisa tu conexión e inténtalo de nuevo.'
                    : 'Esta función no está habilitada en tu entorno.'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activar ventana flotante'),
                subtitle: Text(permissionGranted
                    ? 'Permiso Android concedido'
                    : 'Primero autoriza el permiso de Android'),
                value: enabled && adminOn && permissionGranted,
                onChanged: !adminOn || !permissionGranted
                    ? null
                    : (value) async {
                        await _floatingOffers.settings.setEnabled(value);
                        unawaited(syncDriverPushOverlayState(widget.service, force: true));
                        // Reactivar el ajuste devuelve la burbuja si el conductor la descartó.
                        if (value) {
                          await _floatingOffers.settings.setBubbleDismissed(false);
                        }
                        if (!dialogContext.mounted) return;
                        refresh(() => enabled = value);
                        if (!value) await _floatingOffers.close();
                      },
              ),
              if (adminOn)
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(permissionGranted
                      ? 'Volver a comprobar permiso'
                      : 'Abrir ajustes de Android / Comprobar'),
                  onPressed: () async {
                    if (!permissionGranted) {
                      await _floatingOffers.bridge.openPermissionSettings();
                    }
                    final granted =
                        await _floatingOffers.bridge.hasPermission();
                    if (!dialogContext.mounted) return;
                    refresh(() => permissionGranted = granted);
                    if (!granted) {
                      await _floatingOffers.settings.setEnabled(false);
                      unawaited(syncDriverPushOverlayState(widget.service, force: true));
                      if (!dialogContext.mounted) return;
                      refresh(() => enabled = false);
                      await _floatingOffers.close();
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  // Conductor: la sugerencia aparece una sola vez por viaje, al aceptarlo.
  void _maybePromptOverlayOnDriverTrip(Map<String, dynamic>? trip) {
    final tripId = trip?['id']?.toString();
    if (tripId == null || tripId.isEmpty || tripId == overlayPromptTripId) return;
    overlayPromptTripId = tripId;
    unawaited(_promptOverlayForDriverTrip(tripId));
  }

  Future<void> _promptOverlayForDriverTrip(String tripId) async {
    final isNew = await claimTripOverlayPrompt(tripId, driver: true);
    if (!isNew || !mounted) return;
    await promptOverlayIfNeeded(context, widget.service, driver: true);
  }

  void _showDriverMenu() {
    final data = cachedData;
    if (data?.activeTrip != null || data?.activeDelivery != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finaliza o cancela el servicio activo antes de abrir el menú.',
          ),
        ),
      );
      return;
    }

    final championshipVisibility = hasActiveDriverChampionship();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // La hoja crece con su contenido (sin el límite de media pantalla) y solo
      // desplaza si el contenido supera la altura disponible.
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          // El menú ya tiene más opciones que la altura de la hoja en pantallas
          // pequeñas: sin desplazamiento, la parte inferior se corta.
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: CircleAvatar(
                  backgroundColor: expressBlue,
                  child: Icon(Icons.drive_eta_rounded, color: Colors.white),
                ),
                title: Text(
                  'Modo Conductor',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('Viajes'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('Historial de viajes'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onHistory();
                },
              ),
              ListTile(
                leading: const Icon(Icons.card_giftcard_outlined),
                title: const Text('Retos y referidos'),
                subtitle: const Text('Incentivos para conductores'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(context, MaterialPageRoute<void>(
                    builder: (_) => const BenefitsPage(driver: true),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart_rounded),
                title: const Text('Ganancias'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onEarnings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Mi prioridad'),
                subtitle: FutureBuilder<Map<String, dynamic>>(
                  future: widget.service.myDriverPrioritySummary(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Text('Ver nivel y puntaje');
                    }
                    final enabled = snapshot.data?['enabled'] == true;
                    if (!enabled) {
                      return const Text('Prioridad no habilitada');
                    }
                    final level =
                        snapshot.data?['level']?.toString() ?? 'low';
                    final label = level == 'high'
                        ? 'Alta'
                        : level == 'medium'
                            ? 'Media'
                            : 'Baja';
                    return Text('Nivel $label');
                  },
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverPriorityPage(
                        service: widget.service,
                      ),
                    ),
                  );
                },
              ),
              FutureBuilder<bool>(
                future: championshipVisibility,
                builder: (context, snapshot) {
                  if (snapshot.data != true) {
                    return const SizedBox.shrink();
                  }
                  return ListTile(
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: const Text('Campeonato Express'),
                    subtitle: const Text('Inicio, Top 10 y premios'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DriverChampionshipPage(),
                        ),
                      );
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Seguridad y SOS'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onSafety();
                },
              ),
              ListTile(
                leading: const Icon(Icons.checklist_rtl_rounded),
                title: const Text('Permisos y servicios'),
                subtitle: const Text('Qué está activo y qué falta activar'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverPermissionsPage(
                        service: widget.service,
                      ),
                    ),
                  );
                },
              ),
              // Siempre visible: es el único lugar para activar la burbuja y las
              // ofertas flotantes. Sin permiso, el interruptor queda deshabilitado
              // y el diálogo ofrece abrir los ajustes de Android.
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Ventana flotante'),
                subtitle: const Text('Burbuja fuera de la app'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_showFloatingOfferSettings());
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Mi perfil'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onProfile();
                },
              ),
              if (overlayAllowed)
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: const Text('Llamadas'),
                  subtitle: const Text('Llamadas emergentes en cualquier momento'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CallPreferencesPage(
                          service: widget.service,
                          isDriver: true,
                        ),
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('Cambiar a modo Pasajero'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onSwitchMode();
                },
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  void _syncDriverRequestPopup(_DriverStateData data) {
    if (driverOfferPendingRideId != null) {
      _closeDriverRequestPopup(showNext: false);
      return;
    }
    if (driverRequestQueueAdvancing) return;
    if (!mounted ||
        data.profile['approval_status'] != 'approved' ||
        data.profile['online_status'] != 'online' ||
        data.activeTrip != null ||
        data.activeDelivery != null) {
      _closeDriverRequestPopup(showNext: false);
      return;
    }

    final currentDeliveryPopupId = driverDeliveryPopupId;
    if (currentDeliveryPopupId != null) {
      if (data.deliveries.any(
        (delivery) => delivery['id']?.toString() == currentDeliveryPopupId,
      )) return;
      _closeDriverDeliveryPopup(showNext: false);
    }

    final currentPopupId = driverRequestPopupId;
    if (currentPopupId != null) {
      final stillAvailable = data.rides.any(
        (ride) => ride['id']?.toString() == currentPopupId,
      );
      if (stillAvailable) return;
      _closeDriverRequestPopup(showNext: false);
    }

    final candidates = data.rides.where((ride) {
      final id = ride['id']?.toString();
      if (id == null ||
          id.isEmpty ||
          viewedRideRequestIds.contains(id)) {
        return false;
      }

      if (driverPriorityEnforced) return true;

      final distanceKm = _pickupDistanceKm(
        current,
        asDouble(ride['pickup_latitude']),
        asDouble(ride['pickup_longitude']),
      );
      return distanceKm == null || distanceKm <= 10;
    }).toList();

    if (candidates.isEmpty) {
      for (final delivery in data.deliveries) {
        final id = delivery['id']?.toString();
        if (id != null && id.isNotEmpty &&
            !viewedDeliveryRequestIds.contains(id)) {
          _openDeliveryRequestPopup(delivery);
          break;
        }
      }
      return;
    }

    if (!driverPriorityEnforced) {
      candidates.sort((a, b) {
        final aDistance = _pickupDistanceKm(
              current,
              asDouble(a['pickup_latitude']),
              asDouble(a['pickup_longitude']),
            ) ??
            double.infinity;
        final bDistance = _pickupDistanceKm(
              current,
              asDouble(b['pickup_latitude']),
              asDouble(b['pickup_longitude']),
            ) ??
            double.infinity;

        final distanceCompare = aDistance.compareTo(bDistance);
        if (distanceCompare != 0) return distanceCompare;

        final aTime =
            DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });
    }

    _openDriverRequestPopup(candidates.first);
  }

  Future<void> _loadDriverPopupRoadRoute(
    Map<String, dynamic> ride,
    String popupId, {
    bool delivery = false,
  }) async {
    bool isCurrentPopup() => delivery
        ? driverDeliveryPopupId == popupId : driverRequestPopupId == popupId;
    final pickupLat = asDouble(ride['pickup_latitude']);
    final pickupLng = asDouble(ride['pickup_longitude']);
    final destinationLat = asDouble(ride['destination_latitude']);
    final destinationLng = asDouble(ride['destination_longitude']);
    if (pickupLat == null ||
        pickupLng == null ||
        destinationLat == null ||
        destinationLng == null) {
      return;
    }

    try {
      final pickupPoint = LatLng(pickupLat, pickupLng);
      final destinationPoint = LatLng(destinationLat, destinationLng);
      final points = <LatLng>[];

      if (current != null) {
        final toPickup = await ExpressMapProvider.drivingRoute(
          from: current!,
          to: pickupPoint,
        );
        if (toPickup.provider != 'direct' && toPickup.points.length >= 2) {
          points.addAll(toPickup.points);
        }
      } else {
        points.add(pickupPoint);
      }

      final toDestination = await ExpressMapProvider.drivingRoute(
        from: pickupPoint,
        to: destinationPoint,
      );
      final destinationRoute = toDestination.provider != 'direct' &&
              toDestination.points.length >= 2
          ? toDestination.points
          : const <LatLng>[];
      if (points.isNotEmpty &&
          destinationRoute.isNotEmpty &&
          points.last == destinationRoute.first) {
        points.addAll(destinationRoute.skip(1));
      } else {
        points.addAll(destinationRoute);
      }

      if (!mounted ||
          !isCurrentPopup() ||
          points.length < 2) {
        return;
      }
      setState(() => driverPopupRoadRoute = points);
    } catch (_) {
      // Mantener el mapa utilizable sin dibujar una ruta vial ficticia.
    }
  }

  void _openDriverRequestPopup(
    Map<String, dynamic> ride, {
    bool automatic = true,
  }) {
    final id = ride['id']?.toString();
    if (!mounted || id == null || id.isEmpty) return;

    driverRequestPopupTimer?.cancel();
    viewedRideRequestIds.add(id);

    unawaited(() async {
      try {
        await widget.service.markRideRequestsViewed(<String>[id]);
      } catch (_) {}
    }());

    unawaited(_hydrateDriverRideAddresses(ride));
    // La ventana nunca puede sobrevivir a la vigencia real del servidor.
    final serverDeadline = DateTime.tryParse(
      ride['expires_at']?.toString() ?? '',
    )?.toUtc();
    final visualDeadline =
        DateTime.now().toUtc().add(const Duration(seconds: 30));
    if (serverDeadline == null ||
        !serverDeadline.isAfter(DateTime.now().toUtc())) {
      _dropUnavailableRide(id);
      unawaited(_floatingOffers.invalidateOffer(id));
      return;
    }
    final popupExpiresAt = automatic
        ? (serverDeadline.isBefore(visualDeadline)
            ? serverDeadline : visualDeadline)
        : null;
    setState(() {
      driverRequestPopupId = id;
      driverRequestPopupAutomatic = automatic;
      driverRequestPopupExpiresAt = popupExpiresAt;
      driverRequestPopupRemaining = automatic ? 30 : 0;
      driverPopupRoadRoute = const [];
    });
    _syncDriverFocusNavigation();
    unawaited(_loadDriverPopupRoadRoute(ride, id));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final points = <LatLng>[
        if (current != null) current!,
        if (asDouble(ride['pickup_latitude']) != null &&
            asDouble(ride['pickup_longitude']) != null)
          LatLng(
            asDouble(ride['pickup_latitude'])!,
            asDouble(ride['pickup_longitude'])!,
          ),
        if (asDouble(ride['destination_latitude']) != null &&
            asDouble(ride['destination_longitude']) != null)
          LatLng(
            asDouble(ride['destination_latitude'])!,
            asDouble(ride['destination_longitude'])!,
          ),
      ];
      if (points.length < 2) return;

      var minLat = points.first.latitude;
      var maxLat = points.first.latitude;
      var minLng = points.first.longitude;
      var maxLng = points.first.longitude;
      for (final point in points.skip(1)) {
        minLat = math.min(minLat, point.latitude);
        maxLat = math.max(maxLat, point.latitude);
        minLng = math.min(minLng, point.longitude);
        maxLng = math.max(maxLng, point.longitude);
      }

      mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat, minLng),
            LatLng(maxLat, maxLng),
          ),
          padding: const EdgeInsets.fromLTRB(34, 94, 34, 340),
        ),
      );
    });

    if (!automatic) return;

    // Sonido corto dentro de la app; el popup permanece visible 30 s.
    startExpressAlertSound(durationSeconds: 2);
    driverRequestPopupTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || driverRequestPopupId != id) {
        timer.cancel();
        return;
      }

      final deadline = driverRequestPopupExpiresAt ?? popupExpiresAt;
      final next = deadline == null
          ? 0
          : math.max(
              0,
              (deadline
                          .difference(DateTime.now().toUtc())
                          .inMilliseconds +
                      999) ~/
                  1000,
            ).toInt();

      if (next <= 0) {
        timer.cancel();
        _closeDriverRequestPopup(showNext: true);
        return;
      }

      if (next != driverRequestPopupRemaining) {
        setState(() => driverRequestPopupRemaining = next);
      }
    });
  }

  void _closeDriverRequestPopup({bool showNext = true}) {
    stopExpressAlertSound();
    driverRequestPopupTimer?.cancel();
    driverRequestPopupTimer = null;

    if (mounted &&
        (driverRequestPopupId != null || driverRequestPopupRemaining != 0)) {
      setState(() {
        driverRequestPopupId = null;
        driverRequestPopupAutomatic = false;
        driverRequestPopupRemaining = 0;
        driverRequestPopupExpiresAt = null;
        driverPopupRoadRoute = const [];
      });
    } else {
      driverRequestPopupId = null;
      driverRequestPopupAutomatic = false;
      driverRequestPopupRemaining = 0;
      driverRequestPopupExpiresAt = null;
    }

    // Reject, expire and cancel unlock unless another offer or trip is active.
    _syncDriverFocusNavigation();
    if (showNext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_advanceDriverRequestQueue());
        }
      });
    }
  }

  Future<void> _advanceDriverRequestQueue() async {
    if (!mounted ||
        driverRequestQueueAdvancing ||
        driverRequestPopupId != null ||
        driverDeliveryPopupId != null ||
        driverOfferPendingRideId != null ||
        cachedData?.activeTrip != null ||
        cachedData?.activeDelivery != null) {
      return;
    }

    driverRequestQueueAdvancing = true;
    try {
      final freshRides = driverApprovedWorkKeys.contains('ride') ||
              driverApprovedWorkKeys.contains('parcel')
          ? (await widget.service.availableRideRequests()).where((job) =>
              driverApprovedWorkKeys.contains(
                  job['service_mode'] == 'parcel' ? 'parcel' : 'ride')).toList()
          : <Map<String, dynamic>>[];
      if (!mounted || driverRequestPopupId != null ||
          driverDeliveryPopupId != null) return;

      final candidates = freshRides.where((ride) {
        final id = ride['id']?.toString();
        if (id == null ||
            id.isEmpty ||
            viewedRideRequestIds.contains(id)) {
          return false;
        }

        final distanceKm = _pickupDistanceKm(
          current,
          asDouble(ride['pickup_latitude']),
          asDouble(ride['pickup_longitude']),
        );
        return distanceKm == null || distanceKm <= 10;
      }).toList();

      candidates.sort((a, b) {
        final aDistance = _pickupDistanceKm(
              current,
              asDouble(a['pickup_latitude']),
              asDouble(a['pickup_longitude']),
            ) ??
            double.infinity;
        final bDistance = _pickupDistanceKm(
              current,
              asDouble(b['pickup_latitude']),
              asDouble(b['pickup_longitude']),
            ) ??
            double.infinity;
        final distanceCompare = aDistance.compareTo(bDistance);
        if (distanceCompare != 0) return distanceCompare;

        final aTime =
            DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });

      if (candidates.isNotEmpty) {
        _openDriverRequestPopup(candidates.first);
      } else if (driverApprovedWorkKeys.contains('parcel') ||
          driverApprovedWorkKeys.contains('market')) {
        final deliveries = await widget.service.availableDeliveries();
        if (!mounted || driverRequestPopupId != null ||
            driverDeliveryPopupId != null) return;
        for (final delivery in deliveries) {
          final id = delivery['id']?.toString();
          if (id != null && id.isNotEmpty &&
              expressPrimaryDriverMayReceiveDelivery(
                delivery, driverApprovedWorkKeys,
              ) &&
              !viewedDeliveryRequestIds.contains(id)) {
            _openDeliveryRequestPopup(delivery);
            break;
          }
        }
      }
    } catch (_) {
      // El refresco periódico volverá a consultar si la red falla.
    } finally {
      driverRequestQueueAdvancing = false;
    }
  }

  void _openRequestFromList(Map<String, dynamic> ride) {
    if (driverDeliveryPopupId != null) return;
    _openDriverRequestPopup(ride, automatic: false);
  }

  void _openDeliveryRequestPopup(
    Map<String, dynamic> delivery, {bool automatic = true}
  ) {
    final id = delivery['id']?.toString();
    // Defense in depth: no restaurant courier popup in Express principal.
    if (!expressPrimaryDriverMayReceiveDelivery(
      delivery, driverApprovedWorkKeys,
    )) return;
    if (!mounted || id == null || id.isEmpty ||
        driverRequestPopupId != null || driverOfferPendingRideId != null ||
        driverDeliveryPopupId != null ||
        cachedData?.activeTrip != null || cachedData?.activeDelivery != null) {
      return;
    }
    viewedDeliveryRequestIds.add(id);
    driverDeliveryPopupTimer?.cancel();
    final expires = automatic
        ? DateTime.now().toUtc().add(const Duration(seconds: 30))
        : null;
    setState(() {
      driverDeliveryPopupId = id;
      driverDeliveryPopupAutomatic = automatic;
      driverDeliveryPopupExpiresAt = expires;
      driverDeliveryPopupRemaining = automatic ? 30 : 0;
      driverPopupRoadRoute = const [];
    });
    _syncDriverFocusNavigation();
    unawaited(_loadDriverPopupRoadRoute(
      _asDriverRequest(delivery), id, delivery: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || driverDeliveryPopupId != id) return;
      final a = asDouble(delivery['pickup_latitude']);
      final b = asDouble(delivery['pickup_longitude']);
      final c = asDouble(delivery['dropoff_latitude']);
      final d = asDouble(delivery['dropoff_longitude']);
      if (a != null && b != null && c != null && d != null) {
        mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([
            if (current != null) current!,
            LatLng(a,b), LatLng(c,d),
          ]),
          padding: const EdgeInsets.fromLTRB(34,94,34,340),
        ));
      }
    });
    if (!automatic) return;
    startExpressAlertSound(durationSeconds: 2);
    driverDeliveryPopupTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || driverDeliveryPopupId != id) {
        timer.cancel();
        return;
      }
      final remaining = math.max(0,
          (expires!.difference(DateTime.now().toUtc()).inMilliseconds + 999) ~/ 1000);
      if (remaining <= 0) {
        timer.cancel();
        _closeDriverDeliveryPopup(showNext: true);
        return;
      }
      if (driverDeliveryPopupRemaining != remaining) {
        setState(() => driverDeliveryPopupRemaining = remaining);
      }
    });
  }

  void _closeDriverDeliveryPopup({bool showNext = true}) {
    stopExpressAlertSound();
    driverDeliveryPopupTimer?.cancel();
    driverDeliveryPopupTimer = null;
    if (mounted) {
      setState(() {
        driverDeliveryPopupId = null;
        driverDeliveryPopupRemaining = 0;
        driverDeliveryPopupAutomatic = false;
        driverDeliveryPopupExpiresAt = null;
        driverPopupRoadRoute = const [];
      });
    }
    _syncDriverFocusNavigation();
    if (showNext && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshDriverHome();
      });
    }
  }

  Future<void> _acceptRideFromPopup(Map<String, dynamic> ride) async {
    _closeDriverRequestPopup(showNext: false);
    await _acceptRideAtPassengerFare(ride);
  }

  Future<void> _offerRideFromPopup(Map<String, dynamic> ride) async {
    _closeDriverRequestPopup(showNext: false);
    await _offerRide(ride);
  }

  Future<void> _showDriverRequests(
    List<Map<String, dynamic>> rides,
    List<Map<String, dynamic>> deliveries,
  ) async {
    final categories = <String>[
      for (final key in const ['ride', 'parcel', 'market'])
        if (driverApprovedWorkKeys.contains(key)) key,
    ];
    if (categories.isEmpty) return;
    // All approved jobs share one queue; permission checks stay in the backend.
    var requestAddressHydrationStarted = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, setSheetState) {
        final dark = _riderHomeDark(sheetContext);
        final surface = _riderSurface(sheetContext);
        final softSurface = _riderSoftSurface(sheetContext);
        final border = _riderBorder(sheetContext);
        final textColor = _riderText(sheetContext);
        final muted = _riderMuted(sheetContext);
        final visibleRequests = <Map<String, dynamic>>[
          if (categories.contains('ride'))
            ...rides.where((ride) => ride['service_mode'] != 'parcel'),
          if (categories.contains('parcel'))
            ...rides.where((ride) => ride['service_mode'] == 'parcel'),
          if (categories.contains('parcel'))
            ..._deliveryItemsFor(deliveries, 'parcel'),
          if (categories.contains('market'))
            ..._deliveryItemsFor(deliveries, 'market'),
        ];
        if (!requestAddressHydrationStarted) {
          requestAddressHydrationStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!sheetContext.mounted) return;
            unawaited(() async {
              // Requests can have placeholder labels saved when reverse
              // geocoding was temporarily unavailable during creation. Resolve
              // those labels for the active queue as we already do for the
              // popup and assigned trip screens.
              for (final request in visibleRequests) {
                if (!sheetContext.mounted) break;
                await _hydrateDriverRideAddresses(request);
              }
              if (sheetContext.mounted) setSheetState(() {});
            }());
          });
        }
        return SafeArea(
          top: false,
          child: Container(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 9),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF4A4A4A)
                        : const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Solicitudes activas',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: expressBlue,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          visibleRequests.length.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: Icon(Icons.close_rounded, color: textColor),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: border),
                Expanded(
                  child: visibleRequests.isEmpty
                      ? Center(
                          child: Text(
                            'No hay solicitudes activas.',
                            style: TextStyle(
                              color: muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: visibleRequests.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final ride = visibleRequests[index];
                             final isDelivery = ride['_express_delivery'] == true;
                            final isParcel = ride['service_mode'] == 'parcel';
                            final pickup = _expressDriverRouteLabel(
                              ride,
                              addressKey: 'pickup_address',
                              latitudeKey: 'pickup_latitude',
                              longitudeKey: 'pickup_longitude',
                              fallback: 'Resolviendo ubicación…',
                            );
                            final destination = _expressDriverRouteLabel(
                              ride,
                              addressKey: 'destination_address',
                              latitudeKey: 'destination_latitude',
                              longitudeKey: 'destination_longitude',
                              fallback: 'Resolviendo ubicación…',
                            );
                            final amount =
                                asDouble(ride['proposed_fare']) ?? 0;
                            final distance = _pickupDistanceKm(
                              current,
                              asDouble(ride['pickup_latitude']),
                              asDouble(ride['pickup_longitude']),
                            );
                            final distanceLabel = distance == null
                                ? ''
                                : distance < 1
                                    ? (distance * 1000).round().toString() +
                                        ' m'
                                    : distance.toStringAsFixed(1) + ' km';
                            final tripDistance =
                                asDouble(ride['route_distance_km']);
                            final duration =
                                asDouble(ride['route_duration_minutes'])
                                    ?.round();
                            final category = isParcel ? 'Envíos'
                                : (ride['category']?.toString() ?? 'Viaje');
                            final payment =
                                ride['payment_method']?.toString();

                            Widget metaChip(IconData icon, String label) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: dark
                                      ? const Color(0xFF292929)
                                      : const Color(0xFFF2F4F7),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(color: border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon, size: 12, color: muted),
                                    const SizedBox(width: 4),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return Material(
                              color: softSurface,
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (mounted) {
                                      if (isDelivery) {
                                         _openDeliveryRequestPopup(
                                           ride,
                                           automatic: false,
                                         );
                                       } else {
                                         _openRequestFromList(ride);
                                       }
                                    }
                                  });
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 11, 10, 11),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: dark
                                              ? const Color(0xFF17315E)
                                              : const Color(0xFFEAF2FF),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isDelivery || isParcel
                                               ? Icons.local_shipping_rounded
                                               : Icons.local_taxi_rounded,
                                          color: dark
                                              ? const Color(0xFF79A8FF)
                                              : expressBlue,
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    distanceLabel.isEmpty
                                                        ? category
                                                        : '~' +
                                                            distanceLabel +
                                                            ' al origen',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: muted,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _rideMoney(
                                                    amount,
                                                    ride['currency'],
                                                  ),
                                                  style: TextStyle(
                                                    color: dark
                                                        ? const Color(
                                                            0xFF79A8FF)
                                                        : expressBlue,
                                                    fontSize: 19,
                                                    height: 1,
                                                    fontWeight:
                                                        FontWeight.w900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.trip_origin_rounded,
                                                  size: 13,
                                                  color: muted,
                                                ),
                                                const SizedBox(width: 5),
                                                Expanded(
                                                  child: Text(
                                                    pickup,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: textColor,
                                                      fontSize: 13.5,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.location_on_rounded,
                                                  size: 14,
                                                  color: muted,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    destination,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: muted,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 5,
                                              children: [
                                                metaChip(
                                                  Icons.category_outlined,
                                                  category,
                                                ),
                                                if (tripDistance != null)
                                                  metaChip(
                                                    Icons.route_outlined,
                                                    tripDistance
                                                            .toStringAsFixed(1) +
                                                        ' km',
                                                  ),
                                                if (duration != null)
                                                  metaChip(
                                                    Icons.schedule_rounded,
                                                    duration.toString() +
                                                        ' min',
                                                  ),
                                                if (payment != null)
                                                  metaChip(
                                                    Icons.payments_outlined,
                                                    _paymentLabel(payment),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: muted,
                                        size: 24,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _onConnectivityChanged() {
    // Al recuperar la conexión se sincroniza una sola vez, sin duplicar lecturas.
    if (!mounted || !ExpressConnectivityMonitor.instance.isOnline) return;
    _refreshDriverHome();
  }

  @override
  void dispose() {
    ExpressConnectivityMonitor.instance.removeListener(_onConnectivityChanged);
    timer?.cancel();
    _driverFloatingBarValidityTimer?.cancel();
    driverRequestPopupTimer?.cancel();
    driverDeliveryPopupTimer?.cancel();
    driverOfferPendingTimer?.cancel();
    driverHeatTimer?.cancel();
    positionSubscription?.cancel();
    driverForegroundPushSubscription?.cancel();
    driverRideRequestsChannel?.unsubscribe();
    driverDeliveriesChannel?.unsubscribe();
    driverNotificationsChannel?.unsubscribe();
    driverZoneServicesChannel?.unsubscribe();
    WidgetsBinding.instance.removeObserver(this);
    driverFloatingOfferFocus.removeListener(_onFloatingOfferFocus);
    driverNotificationOfferFocus.removeListener(_onNotificationOfferFocus);
    driverNotificationOfferFocus.value = null;
    _pendingFloatingFocusId = null;
    _pendingFloatingFocusAt = null;
    driverFloatingOfferFocus.value = null;
    unawaited(_floatingOffers.close());
    _floatingOffers.bridge.dispose();
    driverPosition.dispose();
    mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DriverStateData>(
      future: driverFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? cachedData;
        final markers = <Marker>[];
        // Small aggregated cells from authorized searching rides only.
        final heatCircles = <CircleMarker>[];
        final heatMarkers = <Marker>[];
        if (data?.activeTrip == null && data?.activeDelivery == null) {
          for (final cell in driverHeatCells) {
            final latitude = asDouble(cell['latitude']);
            final longitude = asDouble(cell['longitude']);
            final multiplier = asDouble(cell['multiplier']);
            if (latitude == null || longitude == null ||
                multiplier == null || multiplier <= 1.05) continue;
            final level = multiplier >= 4 ? const Color(0xFFEF4444)
                : multiplier >= 3 ? const Color(0xFFF97316)
                : const Color(0xFFF59E0B);
            final point = LatLng(latitude, longitude);
            heatCircles.add(CircleMarker(
              point: point,
              radius: asDouble(cell['radius_m']) ?? 230,
              useRadiusInMeter: true,
              color: level.withValues(alpha: .24),
              borderColor: level.withValues(alpha: .48),
              borderStrokeWidth: 1,
            ));
            final label = multiplier == multiplier.roundToDouble()
                ? multiplier.toStringAsFixed(0)
                : multiplier.toStringAsFixed(1);
            heatMarkers.add(Marker(
              point: point, width: 58, height: 34,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: level, borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white,width: 1.5),
                ),
                child: Text('x$label',style: const TextStyle(
                  color: Colors.white,fontWeight: FontWeight.w900)),
              ),
            ));
          }
        }

        Map<String, dynamic>? driverPopupRide;
        if (driverRequestPopupId != null && data != null) {
          for (final ride in data.rides) {
            if (ride['id']?.toString() == driverRequestPopupId) {
              driverPopupRide = ride;
              break;
            }
          }
        }

        Map<String, dynamic>? driverPopupDelivery;
        if (driverDeliveryPopupId != null && data != null) {
          for (final delivery in data.deliveries) {
            if (delivery['id']?.toString() == driverDeliveryPopupId) {
              driverPopupDelivery = delivery;
              break;
            }
          }
        }

        final driverPopupJob = driverPopupRide ??
            (driverPopupDelivery == null ? null : _asDriverRequest(driverPopupDelivery));

        LatLng? popupPickup;
        LatLng? popupDestination;
        if (driverPopupJob != null) {
          final pickupLat = asDouble(driverPopupJob['pickup_latitude']);
          final pickupLng = asDouble(driverPopupJob['pickup_longitude']);
          final destinationLat =
              asDouble(driverPopupJob['destination_latitude']);
          final destinationLng =
              asDouble(driverPopupJob['destination_longitude']);
          if (pickupLat != null && pickupLng != null) {
            popupPickup = LatLng(pickupLat, pickupLng);
          }
          if (destinationLat != null && destinationLng != null) {
            popupDestination = LatLng(destinationLat, destinationLng);
          }
        }

        if (driverPopupJob != null) {
          if (popupPickup != null) {
            markers.add(
              Marker(
                point: popupPickup,
                width: 46,
                height: 46,
                child: const _RoutePointMapPin(
                  label: 'A',
                  background: expressBlue,
                ),
              ),
            );
          }
          if (popupDestination != null) {
            markers.add(
              Marker(
                point: popupDestination,
                width: 46,
                height: 46,
                child: const _RoutePointMapPin(
                  label: 'B',
                  background: Color(0xFF12B76A),
                ),
              ),
            );
          }
        }

        LatLng? activeTripTarget;
        bool activeTripBeforePickup = false;
        String? activeTripStatus;
        if (driverPopupRide == null && data?.activeTrip != null) {
          final trip = data!.activeTrip!;
          activeTripStatus = trip['status']?.toString() ?? 'driver_assigned';
          final ride = trip['ride_requests'] is Map
              ? Map<String, dynamic>.from(trip['ride_requests'] as Map)
              : <String, dynamic>{};
          final pickupLat = asDouble(ride['pickup_latitude']);
          final pickupLng = asDouble(ride['pickup_longitude']);
          final destinationLat = asDouble(ride['destination_latitude']);
          final destinationLng = asDouble(ride['destination_longitude']);

          activeTripBeforePickup = activeTripStatus == 'driver_assigned' ||
              activeTripStatus == 'driver_arriving';
          final inTrip =
              activeTripStatus == 'in_progress' || activeTripStatus == 'emergency';

          if (activeTripBeforePickup &&
              pickupLat != null &&
              pickupLng != null) {
            activeTripTarget = LatLng(pickupLat, pickupLng);
          } else if (inTrip &&
              destinationLat != null &&
              destinationLng != null) {
            activeTripTarget = LatLng(destinationLat, destinationLng);
          }

          if (activeTripTarget != null) {
            markers.add(
              Marker(
                point: activeTripTarget,
                width: 50,
                height: 50,
                child: _MapPin(
                  icon: activeTripBeforePickup
                      ? Icons.trip_origin_rounded
                      : Icons.location_on_rounded,
                  dark: true,
                ),
              ),
            );

            if (current != null) {
              _refreshDriverActiveRoadRoute(
                trip['id'].toString(),
                activeTripStatus,
                current!,
                activeTripTarget,
              );
              final stageKey =
                  trip['id'].toString() + ':' + activeTripStatus.toString();
              if (driverMapTripStageKey != stageKey) {
                driverMapTripStageKey = stageKey;
                final origin = current!;
                final target = activeTripTarget;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints([origin, target]),
                      padding: const EdgeInsets.fromLTRB(46, 120, 46, 330),
                    ),
                  );
                });
              }
            }
          } else {
            driverMapTripStageKey = null;
            driverActiveRoadRouteKey = null;
            driverActiveRoadRoute = const [];
          }
        }

        final hasActiveDriverService =
            data?.activeTrip != null || data?.activeDelivery != null;
        final hasPendingDriverRating = data?.pendingRating != null;

        return Scaffold(
          body: Stack(
            children: [
              // Hijo no posicionado que ocupa el cuerpo: sin él, el Stack
              // queda sin tamaño cuando aparece la oferta (popup) y la
              // pantalla se vuelve blanca.
              const SizedBox.expand(),
              Positioned.fill(
                child: FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: current ?? expressFallback,
                    initialZoom: current == null ? 13 : 15,
                    onPositionChanged: (camera, _) {
                      if ((camera.zoom - driverMapZoom).abs() < .04) return;
                      setState(() => driverMapZoom = camera.zoom);
                    },
                  ),
                  children: [
                    _expressMapTileLayer(context),
                    if (driverPopupJob == null && heatCircles.isNotEmpty)
                      CircleLayer(circles: heatCircles),
                    if (driverPopupJob == null && heatMarkers.isNotEmpty)
                      MarkerLayer(markers: heatMarkers),
                    if (driverPopupJob != null)
                      PolylineLayer(
                        polylines: [
                          if (driverPopupRoadRoute.length > 1)
                            Polyline(
                              points: driverPopupRoadRoute,
                              strokeWidth: 5,
                              color: expressBlue,
                            )
                        ],
                      ),
                    if (driverPopupJob == null &&
                        activeTripTarget != null)
                      ValueListenableBuilder<LatLng?>(
                        valueListenable: driverPosition,
                        builder: (context, point, _) {
                          if (point == null) return const SizedBox.shrink();
                          if (driverActiveRoadRoute.length < 2) {
                            return const SizedBox.shrink();
                          }
                          return PolylineLayer(
                            polylines: [
                              Polyline(
                                points: driverActiveRoadRoute,
                                strokeWidth: 5,
                                color: expressBlue,
                              ),
                            ],
                          );
                        },
                      ),
                    ValueListenableBuilder<LatLng?>(
                      valueListenable: driverPosition,
                      builder: (context, point, _) {
                        if (point == null) return const SizedBox.shrink();
                        return MarkerLayer(
                          markers: [
                            Marker(
                              point: point,
                              width: 52,
                              height: 52,
                              child: Transform.scale(
                                scale: _expressMapMarkerScale(driverMapZoom),
                                child: ExpressMapVehicleMarker(
                                  key: ValueKey('own-driver-${widget.service.userId}'),
                                  vehicleType: driverMapVehicleType,
                                  headingDegrees: driverMapHeading.degrees,
                                  navigating: const {'in_progress', 'emergency'}
                                      .contains(data?.activeTrip?['status']) ||
                                      const {'in_progress', 'picked_up', 'out_for_delivery'}
                                          .contains(data?.activeDelivery?['status']),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (markers.isNotEmpty) MarkerLayer(markers: markers),
                    const ExpressMapAttribution(),
                  ],
                ),
              ),
              Positioned(
                top: 2,
                left: 10,
                right: 10,
                child: SafeArea(
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      // Stable independent slots: a status change, first-load
                      // placeholder or a larger earning never shifts center.
                      final statusWidth = width < 380 ? 100.0
                          : width < 520 ? 112.0 : 150.0;
                      final earningsWidth = math.min(
                        width < 520 ? 178.0 : 258.0,
                        math.max(110.0, width - 2 * (statusWidth + 8.0)),
                      );
                      // Con el detalle de una solicitud abierto, menú y "En línea"
                      // se ocultan para que la cabecera de la solicitud quede arriba.
                      // Also while an offer waits for the passenger (oferta enviada).
                      if (driverRequestPopupId != null ||
                          driverOfferPendingRideId != null) {
                        return const SizedBox.shrink();
                      }
                      return SizedBox(
                        height: 72,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.topCenter,
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: _CircleButton(
                                icon: Icons.menu_rounded,
                                onPressed: _showDriverMenu,
                                enabled: !hasActiveDriverService,
                              ),
                            ),
                            // Only the idle driver's main map shows earnings.
                            // Hide it during rides, deliveries and incoming offers.
                            if (!hasActiveDriverService && driverPopupJob == null)
                              Align(
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: earningsWidth,
                                  child: _DriverDailyEarningsBadge(
                                    service: widget.service,
                                    onDetails: widget.onEarnings,
                                  ),
                                ),
                              ),
                            Align(
                              alignment: Alignment.topRight,
                              child: SizedBox(
                                width: statusWidth,
                                height: 50,
                                child: data == null
                                    ? Center(child: Material(
                                        color: const Color(0xFF22252D),
                                        borderRadius:
                                            BorderRadius.circular(30),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 12),
                                          child: Text(
                                            'Verificando…',
                                            maxLines: 1,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11),
                                          ),
                                        ),
                                      ))
                                    : FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.topRight,
                                        child: _OnlineBadge(
                                          approved: data.profile[
                                              'approval_status'] == 'approved',
                                          // Con un servicio activo el servidor deja
                                          // al conductor en 'busy': sigue conectado.
                                          // El botón ya está bloqueado (locked), así
                                          // que el color verde no cambia.
                                          online: hasActiveDriverService
                                              ? (data.profile['online_status']
                                                      == 'online' ||
                                                  data.profile['online_status']
                                                      == 'busy')
                                              : data.profile['online_status']
                                                  == 'online',
                                          busy: busy,
                                          locked: hasActiveDriverService,
                                          onPressed: () =>
                                              _toggleOnline(data.profile),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (driverPopupRide != null)
                Positioned.fill(
                  child: _DriverRequestPopup(
                    ride: driverPopupRide,
                    current: current,
                    remainingSeconds: driverRequestPopupRemaining,
                    automatic: driverRequestPopupAutomatic,
                    onClose: () => _closeDriverRequestPopup(
                      showNext: driverRequestPopupAutomatic,
                    ),
                    onOffer: () =>
                        _offerRideFromPopup(driverPopupRide!),
                    onQuickOffer: (amount) =>
                        _quickOfferRide(driverPopupRide!, amount),
                    onAccept: () =>
                        _acceptRideFromPopup(driverPopupRide!),
                  ),
                ),
              if (driverPopupDelivery != null)
                Positioned.fill(
                  child: _DriverRequestPopup(
                    ride: _asDriverRequest(driverPopupDelivery),
                    current: current,
                    automatic: driverDeliveryPopupAutomatic,
                    remainingSeconds: driverDeliveryPopupRemaining,
                    onClose: () => _closeDriverDeliveryPopup(
                      showNext: driverDeliveryPopupAutomatic,
                    ),
                    onAccept: () => _submitDriverDeliveryOffer(
                      driverPopupDelivery!, asDouble(
                        driverPopupDelivery['proposed_fare']) ?? 0,
                    ),
                    onQuickOffer: (amount) =>
                        _submitDriverDeliveryOffer(driverPopupDelivery!, amount),
                    onOffer: () => _customDeliveryOffer(driverPopupDelivery!),
                  ),
                ),
              if (driverPopupRide == null && driverPopupDelivery == null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 14, bottom: 8),
                          child: _CircleButton(
                            icon: Icons.my_location_rounded,
                            onPressed: () async {
                              driverFollowLocation = true;
                              await _locate(recenter: true);
                            },
                          ),
                        ),
                      ),
                      AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height *
                            (hasActiveDriverService
                                ? .64
                                : hasPendingDriverRating
                                    ? .62
                                    : .48),
                      ),
                      child: Builder(
                        builder: (context) {
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              data == null) {
                            return _PanelShell(
                              controller: null,
                              children: const [
                                Center(child: CircularProgressIndicator()),
                              ],
                            );
                          }
                          if (snapshot.hasError || data == null) {
                            return _PanelShell(
                              controller: null,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 42,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  snapshot.error?.toString() ??
                                      'No se pudo cargar el modo conductor.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            );
                          }
                          return _DriverBottomPanel(
                            controller: null,
                            data: data,
                            transitionBusy: busy,
                            current: current,
                            onToggle: () => _toggleOnline(data.profile),
                            onRequests: () => _showDriverRequests(data.rides, data.deliveries),
                            onDelivery: _claimDelivery,
                            onTripTracking: _openTripInWaze,
                            onDeliveryTracking: _openDeliveryTracking,
                            onAdvanceTrip: _advanceTrip,
                            onAdvanceDelivery: _advanceDelivery,
                            onCancelTrip: _cancelDriverTrip,
                            onCancelDelivery: _cancelDriverDelivery,
                            onRatePending: _ratePending,
                          );
                        },
                      ),
                    ),
                  ),
                    ],
                  ),
                ),
              if (driverOfferPendingRideId != null &&
                  data?.activeTrip == null)
                Positioned.fill(
                  child: _DriverOfferWaitingOverlay(
                    remainingSeconds: driverOfferPendingRemaining,
                  ),
                ),
            
              const ExpressOfflineBanner(),
            ],
          ),
        );
      },
    );
  }
}

class _DriverOfferWaitingOverlay extends StatelessWidget {
  final int remainingSeconds;

  const _DriverOfferWaitingOverlay({
    required this.remainingSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = remainingSeconds.clamp(0, 30);
    final progress = seconds / 30;
    final dark = _riderHomeDark(context);
    final surface = dark ? const Color(0xFF171717) : Colors.white;
    final muted = dark ? const Color(0xFFB7BDC8) : expressMuted;

    // Tarjeta centrada con velo transparente que absorbe todos los toques:
    // mientras la oferta espera respuesta no se usan mapa, botones ni navegación.
    return Stack(
      children: [
        const Positioned.fill(
          child: ModalBarrier(dismissible: false, color: Colors.transparent),
        ),
        Material(
          color: Colors.transparent,
          child: SafeArea(
            // Centro del área libre entre la cabecera y el panel inferior (no sobre el panel).
            child: Align(
              alignment: Alignment(
                0,
                visibleAreaCenterAlignmentY(
                  viewportHeight: MediaQuery.sizeOf(context).height,
                  topInset: MediaQuery.paddingOf(context).top + 72,
                  bottomOccludedHeight: .36 * MediaQuery.sizeOf(context).height,
                ),
              ),
              child: Container(
              width: 290,
              // Deja libre el botón de ubicación del lado derecho.
              // Márgenes simétricos: el cuadro queda centrado en el área libre.
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 6,
                          strokeCap: StrokeCap.round,
                        ),
                        Text(
                          '$seconds',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Esperando confirmación del pasajero',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _riderText(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu oferta ya fue enviada. Mientras esperas no recibirás ni podrás aceptar otra solicitud.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
    );
  }
}

class _DriverRequestPopup extends StatelessWidget {
  final Map<String, dynamic> ride;
  final LatLng? current;
  final int remainingSeconds;
  final bool automatic;
  final VoidCallback onClose;
  final VoidCallback onOffer;
  final ValueChanged<num> onQuickOffer;
  final VoidCallback onAccept;

  const _DriverRequestPopup({
    required this.ride,
    required this.current,
    required this.remainingSeconds,
    required this.automatic,
    required this.onClose,
    required this.onOffer,
    required this.onQuickOffer,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final pickup = _expressDriverRouteLabel(
      ride,
      addressKey: 'pickup_address',
      latitudeKey: 'pickup_latitude',
      longitudeKey: 'pickup_longitude',
      fallback: 'Resolviendo ubicación…',
    );
    final destination = _expressDriverRouteLabel(
      ride,
      addressKey: 'destination_address',
      latitudeKey: 'destination_latitude',
      longitudeKey: 'destination_longitude',
      fallback: 'Resolviendo ubicación…',
    );
    final fare = asDouble(ride['proposed_fare']) ?? 0;
    final tripKm = asDouble(ride['route_distance_km']);
    final category = ride['service_mode'] == 'parcel' ? 'Envíos'
        : (ride['category']?.toString() ?? 'Viaje');
    final payment = ride['payment_method']?.toString();
    final pickupDistance = _pickupDistanceKm(
      current,
      asDouble(ride['pickup_latitude']),
      asDouble(ride['pickup_longitude']),
    );
    final dark = _riderHomeDark(context);
    final panel = dark ? const Color(0xFF161616) : Colors.white;
    final soft = dark ? const Color(0xFF232323) : const Color(0xFFF5F7FA);
    final backendSteps = ride['quick_offer_steps'];
    final fallback = ride['currency']?.toString().toUpperCase() == 'CLP'
        ? <num>[250, 500, 750]
        : <num>[1, 2, 3];
    final steps = backendSteps is List && backendSteps.length == 3
        ? backendSteps.map((v) => asDouble(v) ?? 0).toList()
        : fallback.map((v) => v.toDouble()).toList();
    final quick1 = fare + steps[0];
    final quick2 = fare + steps[1];
    final quick3 = fare + steps[2];

    final info = <Widget>[
      _JobInfoPill(icon: Icons.category_outlined, label: category),
      if (pickupDistance != null)
        _JobInfoPill(
          icon: Icons.near_me_outlined,
          label: pickupDistance < 1
              ? '${(pickupDistance * 1000).round()} m al origen'
              : '${pickupDistance.toStringAsFixed(1)} km al origen',
        ),
      if (tripKm != null)
        _JobInfoPill(
          icon: Icons.route_outlined,
          label: '${tripKm.toStringAsFixed(1)} km de viaje',
        ),
      if (payment != null)
        _JobInfoPill(
          icon: Icons.payments_outlined,
          label: _paymentLabel(payment),
        ),
    ];

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Stack(
          children: [
            // Con el detalle abierto la barra superior está oculta: la cabecera sube
            // hasta el área segura conservando sus controles.
            Positioned(
              top: 8,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .58),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        ride['_express_delivery'] == true
                            ? ride['marketplace_order_id'] == null
                                ? 'Solicitud de envío'
                                : 'Solicitud de restaurante'
                            : ride['service_mode'] == 'parcel'
                                ? 'Solicitud de envío'
                                : 'Solicitud de viaje',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 54),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .64),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      automatic
                          ? '${remainingSeconds.clamp(0, 30)} s'
                          : 'Detalle',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 24,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: dark
                              ? const Color(0xFF4A4A4A)
                              : const Color(0xFFD0D5DD),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _rideMoney(fare, ride['currency']),
                            style: TextStyle(
                              color: _riderText(context),
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          ride['_express_delivery'] == true
                              ? ride['marketplace_order_id'] != null
                                  ? 'Tarifa del pedido'
                                  : 'Tarifa del envío'
                              : ride['service_mode'] == 'parcel'
                                  ? 'Tarifa del envío'
                                  : 'Tarifa del pasajero',
                          style: TextStyle(
                            color: _riderMuted(context),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    SizedBox(
                      height: 31,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: info.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 6),
                        itemBuilder: (_, index) => info[index],
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _riderBorder(context)),
                      ),
                      child: Column(
                        children: [
                          _DriverRouteLine(
                            icon: Icons.trip_origin_rounded,
                            text: 'A · ' + pickup,
                          ),
                          const SizedBox(height: 5),
                          _DriverRouteLine(
                            icon: Icons.location_on_rounded,
                            text: 'B · ' + destination,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 49,
                      child: FilledButton(
                        onPressed: onAccept,
                        style: FilledButton.styleFrom(
                          backgroundColor: expressBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Aceptar por ' +
                              _rideMoney(fare, ride['currency']),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        for (final amount in [quick1, quick2, quick3]) ...[
                          if (amount != quick1) const SizedBox(width: 6),
                          Expanded(
                            child: SizedBox(
                              height: 42,
                              child: OutlinedButton(
                                onPressed: ride['_express_delivery'] == true &&
                                        ride['marketplace_order_id'] != null
                                    ? null : () => onQuickOffer(amount),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(
                                  '+ ' +
                                      _rideMoney(
                                        amount - fare,
                                        ride['currency'],
                                      ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    SizedBox(
                      height: 42,
                      width: double.infinity,
                      child: TextButton(
                        onPressed: onClose,
                        style: TextButton.styleFrom(
                          foregroundColor: _riderMuted(context),
                        ),
                        child: const Text('Ignorar oferta'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverBottomPanel extends StatelessWidget {
  final ScrollController? controller;
  final _DriverStateData data;
  final bool transitionBusy;
  final LatLng? current;
  final VoidCallback onToggle;
  final VoidCallback onRequests;
  final ValueChanged<Map<String, dynamic>> onDelivery;
  final ValueChanged<Map<String, dynamic>> onTripTracking;
  final ValueChanged<Map<String, dynamic>> onDeliveryTracking;
  final ValueChanged<Map<String, dynamic>> onAdvanceTrip;
  final ValueChanged<Map<String, dynamic>> onAdvanceDelivery;
  final ValueChanged<Map<String, dynamic>> onCancelTrip;
  final ValueChanged<Map<String, dynamic>> onCancelDelivery;
  final ValueChanged<Map<String, dynamic>> onRatePending;

  const _DriverBottomPanel({
    required this.controller,
    required this.data,
    required this.transitionBusy,
    required this.current,
    required this.onToggle,
    required this.onRequests,
    required this.onDelivery,
    required this.onTripTracking,
    required this.onDeliveryTracking,
    required this.onAdvanceTrip,
    required this.onAdvanceDelivery,
    required this.onCancelTrip,
    required this.onCancelDelivery,
    required this.onRatePending,
  });

  @override
  Widget build(BuildContext context) {
    final approved = data.profile['approval_status'] == 'approved';
    final online = data.profile['online_status'] == 'online';
    final activeIsRestaurantOrder =
        data.activeDelivery?['marketplace_order_id'] != null;

    return _PanelShell(
      controller: controller,
      darkSurface: _riderHomeDark(context),
      // When the outer driver tabs are hidden, preserve Android's gesture
      // navigation safe area for the Arrived/Finish/Cancel trip actions.
      bottomPadding: data.activeTrip != null || data.activeDelivery != null
          ? 8 + MediaQuery.viewPaddingOf(context).bottom
          : 6,
      children: [
        if (data.pendingRating != null) ...[
          _PendingRatingCard(
            pending: data.pendingRating!,
            onTap: () => onRatePending(data.pendingRating!),
            counterpartLabel: data.pendingRating!['service_mode'] == 'parcel'
                ? 'cliente del envío' : 'pasajero',
          ),
          const SizedBox(height: 10),
        ],
        if (data.activeTrip != null)
          _DriverActiveTripCard(
            trip: data.activeTrip!,
            passenger: data.counterpart,
            onMap: () => onTripTracking(data.activeTrip!),
            onChat: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceChatPage(
                  service: data.service,
                  title: _expressIsParcelTrip(data.activeTrip!)
                       ? 'Chat del envío' : 'Chat del viaje',
                  tripId: data.activeTrip!['id'].toString(),
                ),
              ),
            ),
            onCall: () => _expressIsParcelTrip(data.activeTrip!)
                ? ExpressPrivateVoiceCall.instance.chooseParcelCallTarget(
                    context: context,
                    service: data.service,
                    trip: data.activeTrip!,
                  )
                : ExpressPrivateVoiceCall.instance.startTripCall(
                    context: context,
                    service: data.service,
                    trip: data.activeTrip!,
                  ),
            primaryLabel: _driverTripNextLabel(
              data.activeTrip!['status']?.toString(),
              parcel: _expressIsParcelTrip(data.activeTrip!),
            ),
            onPrimary: _driverTripNextLabel(
                      data.activeTrip!['status']?.toString(),
                      parcel: _expressIsParcelTrip(data.activeTrip!),
                    ) !=
                    null
                ? () => onAdvanceTrip(data.activeTrip!)
                : null,
            onCancel: ['driver_assigned', 'driver_arriving', 'driver_waiting']
                    .contains(data.activeTrip!['status']?.toString())
                ? () => onCancelTrip(data.activeTrip!)
                : null,
          )
        else if (data.activeDelivery != null)
          _ActiveCard(
            icon: Icons.local_shipping_rounded,
            title: data.counterpart?['full_name']?.toString().trim().isNotEmpty == true
                ? data.counterpart!['full_name'].toString()
                : 'Cliente',
            subtitle: _deliveryStatus(
              data.activeDelivery!['status']?.toString(),
              restaurantOrder: activeIsRestaurantOrder,
            ),
            detail: activeIsRestaurantOrder
                ? 'Cliente del restaurante'
                : 'Cliente del delivery',
            onMap: () => onDeliveryTracking(data.activeDelivery!),
            onChat: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceChatPage(
                  service: data.service,
                  title: activeIsRestaurantOrder
                      ? 'Chat del pedido'
                      : 'Chat del delivery',
                  deliveryId: data.activeDelivery!['id'].toString(),
                ),
              ),
            ),
            onCall: () => callExpressNumber(
              context,
              data.counterpart?['phone']?.toString(),
            ),
            primaryLabel: _driverDeliveryNextLabel(
              data.activeDelivery!['status']?.toString(),
              restaurantOrder: activeIsRestaurantOrder,
            ),
            onPrimary: _driverDeliveryNextLabel(
                      data.activeDelivery!['status']?.toString(),
                      restaurantOrder: activeIsRestaurantOrder,
                    ) !=
                    null
                ? () => onAdvanceDelivery(data.activeDelivery!)
                : null,
            dangerLabel: data.activeDelivery!['status'] == 'accepted'
                ? 'Cancelar'
                : null,
            onDanger: data.activeDelivery!['status'] == 'accepted'
                ? () => onCancelDelivery(data.activeDelivery!)
                : null,
          )
        else if (!approved)
          const _NoticeCard(
            icon: Icons.hourglass_top_rounded,
            title: 'Aprobación pendiente',
            subtitle:
                'Completa tu licencia y los datos del vehículo. Te avisaremos cuando tu perfil esté listo.',
          )
        else if (!online) ...[
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  color: expressBlue,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estás fuera de línea',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Actívate para recibir solicitudes.',
                      style: TextStyle(
                        color: expressMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: transitionBusy ? null : onToggle,
              icon: transitionBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.power_settings_new_rounded,
                      size: 19,
                    ),
              label: Text(
                transitionBusy ? 'Activando…' : 'Ponerme en línea',
              ),
            ),
          ),
        ] else ...[
          _DriverRequestsButton(
            count: data.rides.length + data.deliveries.length,
            onTap: onRequests,
          ),
          const SizedBox(height: 10),
          if (data.rides.isEmpty && data.deliveries.isEmpty)
            const _NoticeCard(
              icon: Icons.radar_rounded,
              title: 'Esperando solicitudes…',
              subtitle:
                  'Cuando llegue un viaje o una entrega aparecerá aquí automáticamente.',
            )
          else if (data.rides.isNotEmpty)
            const _NoticeCard(
              icon: Icons.notifications_active_outlined,
              title: 'Buscando viajes cerca',
              subtitle:
                  'La solicitud prioritaria aparece arriba. Toca “Solicitudes” para ver todas.',
            )
          else
            _NoticeCard(
              icon: Icons.local_shipping_outlined,
              title: data.deliveries.any(
                      (delivery) => delivery['marketplace_order_id'] != null)
                  ? 'Pedido de restaurante disponible'
                  : 'Envío disponible',
              subtitle:
                  'Toca Solicitudes para ver envíos y pedidos disponibles.',
            ),
        ],
      ],
    );
  }
}

class _DriverRequestsButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _DriverRequestsButton({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final surface = dark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = _riderBorder(context);
    final textColor = _riderText(context);
    final muted = _riderMuted(context);
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF17315E)
                      : const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.inbox_rounded,
                  color: expressBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitudes',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ver solicitudes activas',
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 34),
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: count > 0
                      ? expressBlue
                      : dark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  count.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: count > 0 ? Colors.white : muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  final double distanceKm;
  final int durationMinutes;
  final num fare;
  final String currencyCode;
  final bool routing;
  final bool quoting;
  final bool showFare;
  final bool fareReady;

  const _RouteSummary({
    required this.distanceKm,
    required this.durationMinutes,
    required this.fare,
    required this.currencyCode,
    required this.routing,
    required this.quoting,
    this.showFare = true,
    this.fareReady = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: _riderHomeDark(context)
            ? const Color(0xFF15233D)
            : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _riderHomeDark(context)
              ? const Color(0xFF284A7F)
              : const Color(0xFFCFE0FF),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_rounded, color: expressBlue, size: 21),
          const SizedBox(width: 9),
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _RouteMetric(
                  icon: Icons.straighten_rounded,
                  text: distanceKm.toStringAsFixed(1) + ' km',
                ),
                _RouteMetric(
                  icon: Icons.schedule_rounded,
                  text: durationMinutes.toString() + ' min',
                ),
                if (showFare)
                  _RouteMetric(
                    icon: Icons.payments_outlined,
                    text: quoting
                        ? 'Calculando tarifa…'
                        : fareReady
                            ? 'Sugerido ' + _rideMoney(fare, currencyCode)
                            : 'Tarifa pendiente',
                  ),
              ],
            ),
          ),
          if (routing || quoting)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteMetric extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RouteMetric({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: expressBlue),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            color: _riderText(context),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PendingRatingCard extends StatelessWidget {
  final Map<String, dynamic> pending;
  final VoidCallback onTap;
  final String counterpartLabel;

  const _PendingRatingCard({
    required this.pending,
    required this.onTap,
    this.counterpartLabel = 'persona',
  });

  @override
  Widget build(BuildContext context) {
    final kind = pending['kind']?.toString() ?? 'trip';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFE2A8)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFFFEBC2),
              child: Icon(
                Icons.star_rounded,
                color: Color(0xFFD98A00),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Califica al ${kind == 'delivery' ? 'repartidor' : counterpartLabel}',
                    style: const TextStyle(
                      color: expressDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Toca aquí para dejar tu calificación.',
                    style: TextStyle(
                      color: expressMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: expressMuted),
          ],
        ),
      ),
    );
  }
}

double? _pickupDistanceKm(
  LatLng? current,
  double? latitude,
  double? longitude,
) {
  if (current == null || latitude == null || longitude == null) return null;
  final meters = const Distance().as(
    LengthUnit.Meter,
    current,
    LatLng(latitude, longitude),
  );
  return meters / 1000;
}

class _PanelShell extends StatelessWidget {
  final ScrollController? controller;
  final List<Widget> children;
  final bool darkSurface;
  final double? bottomPadding;

  const _PanelShell({
    required this.controller,
    required this.children,
    this.darkSurface = false,
    this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: darkSurface ? const Color(0xFF121212) : Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Builder(
        builder: (context) {
          final content = <Widget>[
            if (controller != null) ...[
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: darkSurface
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ] else
              const SizedBox(height: 4),
            ...children,
          ];
          final padding = EdgeInsets.fromLTRB(
            16,
            6,
            16,
            bottomPadding ?? 18 + MediaQuery.viewPaddingOf(context).bottom,
          );

          if (controller == null) {
            return SingleChildScrollView(
              primary: false,
              physics: const ClampingScrollPhysics(),
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: content,
              ),
            );
          }

          return ListView(
            controller: controller,
            primary: false,
            padding: padding,
            children: content,
          );
        },
      ),
    );
  }
}

class _RiderSectionTitle extends StatelessWidget {
  final String text;

  const _RiderSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: _riderText(context),
      ),
    );
  }
}

class _HomeDestinationSearch extends StatelessWidget {
  final String serviceType;
  final VoidCallback onTap;

  const _HomeDestinationSearch({
    required this.serviceType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _riderSoftSurface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _riderBorder(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _riderHomeDark(context)
                    ? const Color(0xFF262626)
                    : const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.search_rounded,
                color: _riderMuted(context),
                size: 23,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                serviceType == 'ride'
                    ? '¿A dónde quieres ir?'
                    : '¿Dónde entregamos?',
                style: TextStyle(
                  color: _riderMuted(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: _riderMuted(context),
              size: 23,
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedPlacesGrid extends StatelessWidget {
  final List<Map<String, dynamic>> saved;
  final ValueChanged<Map<String, dynamic>> onSaved;
  final VoidCallback onManage;

  const _SavedPlacesGrid({
    required this.saved,
    required this.onSaved,
    required this.onManage,
  });

  Map<String, dynamic>? _byLabel(String value) {
    for (final row in saved) {
      if (row['label']?.toString().trim().toLowerCase() ==
          value.toLowerCase()) {
        return row;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final home = _byLabel('casa');
    final work = _byLabel('trabajo');
    return Row(
      children: [
        Expanded(
          child: _SavedPlaceTile(
            icon: Icons.home_outlined,
            title: 'Casa',
            subtitle: home?['address']?.toString(),
            onTap: home == null ? onManage : () => onSaved(home),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SavedPlaceTile(
            icon: Icons.work_outline_rounded,
            title: 'Trabajo',
            subtitle: work?['address']?.toString(),
            onTap: work == null ? onManage : () => onSaved(work),
          ),
        ),
      ],
    );
  }
}

class _SavedPlaceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SavedPlaceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final empty = subtitle == null || subtitle!.trim().isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _riderSurface(context),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _riderBorder(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _riderHomeDark(context)
                    ? const Color(0xFF262626)
                    : const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _riderText(context), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _riderText(context),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    empty ? 'Agregar' : subtitle!,
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
      ),
    );
  }
}

class _CompactRoutePoints extends StatelessWidget {
  final PickedLocation? pickup;
  final PickedLocation destination;
  final VoidCallback onPickup;
  final VoidCallback onDestination;

  const _CompactRoutePoints({
    required this.pickup,
    required this.destination,
    required this.onPickup,
    required this.onDestination,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AddressTile(
          icon: Icons.trip_origin_rounded,
          text: pickup?.label ?? 'Elegir punto de partida',
          onTap: onPickup,
        ),
        const SizedBox(height: 8),
        _AddressTile(
          icon: Icons.location_on_rounded,
          text: destination.label,
          onTap: onDestination,
        ),
      ],
    );
  }
}

class _AddressTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool prominent = false;

  const _AddressTile({
    required this.icon,
    required this.text,
    required this.onTap,

  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: prominent
              ? (_riderHomeDark(context)
                  ? const Color(0xFF262626)
                  : const Color(0xFFF2F4F7))
              : _riderSoftSurface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _riderBorder(context)),
        ),
        child: Row(
          children: [
            Icon(icon, color: expressBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight:
                      prominent ? FontWeight.w900 : FontWeight.w700,
                  color: prominent
                      ? _riderText(context)
                      : _riderMuted(context),
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

/// Collapses parcel details inside the existing Taxi chooser (no new flow).
class _ParcelCollapsedFields extends StatefulWidget {
  final TextEditingController fromName;
  final TextEditingController fromPhone;
  final TextEditingController toName;
  final TextEditingController toPhone;
  final TextEditingController description;
  final int photos;
  final bool uploading;
  final VoidCallback onPhotos;
  const _ParcelCollapsedFields({
    required this.fromName, required this.fromPhone,
    required this.toName, required this.toPhone,
    required this.description, required this.photos,
    required this.uploading, required this.onPhotos,
  });
  @override
  State<_ParcelCollapsedFields> createState() => _ParcelCollapsedFieldsState();
}

class _ParcelCollapsedFieldsState extends State<_ParcelCollapsedFields> {
  // 0=sender, 1=recipient, 2=optional package description, -1=closed.
  int open = 0;
  bool complete(TextEditingController a, TextEditingController b) =>
      a.text.trim().isNotEmpty && b.text.trim().isNotEmpty;

  Widget field(TextEditingController c, String label, {bool phone = false,
      int? after}) => TextField(
    controller: c,
    onChanged: (_) => setState(() {}),
    keyboardType: phone ? TextInputType.phone : TextInputType.name,
    textInputAction: phone ? TextInputAction.done : TextInputAction.next,
    onSubmitted: (_) {
      if (phone && after != null) {
        FocusScope.of(context).unfocus();
        setState(() => open = after);
      } else if (!phone) {
        FocusScope.of(context).nextFocus();
      }
    },
    decoration: InputDecoration(labelText: label, isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
  );

  Widget header(int which, String title, String summary, bool ready) =>
      InkWell(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => open = open == which ? -1 : which);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(ready ? Icons.check_circle_rounded :
                Icons.circle_outlined, size: 17,
                color: ready ? const Color(0xFF17975A) : expressBlue),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: _riderText(context),
                  fontWeight: FontWeight.w800, fontSize: 13)),
                if (open != which) Text(summary,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _riderMuted(context), fontSize: 11)),
              ],
            )),
            Icon(open == which ? Icons.expand_less : Icons.expand_more,
              color: _riderMuted(context)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fromReady = complete(widget.fromName, widget.fromPhone);
    final toReady = complete(widget.toName, widget.toPhone);
    final optional = widget.description.text.trim().isNotEmpty ||
        widget.photos > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _riderSoftSurface(context),
        border: Border.all(color: _riderBorder(context)),
        borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Datos del paquete', style: TextStyle(
            color: _riderText(context), fontWeight: FontWeight.w900)),
          header(0, 'Remitente',
            fromReady ? widget.fromName.text.trim() :
              'Completar contacto de recogida', fromReady),
          if (open == 0) ...[
            field(widget.fromName, 'Nombre del remitente'),
            const SizedBox(height: 6),
            field(widget.fromPhone, 'Teléfono del remitente',
              phone: true, after: fromReady ? 1 : null),
          ],
          Divider(color: _riderBorder(context), height: 13),
          header(1, 'Destinatario',
            toReady ? widget.toName.text.trim() :
              'Completar contacto de entrega', toReady),
          if (open == 1) ...[
            field(widget.toName, 'Nombre del destinatario'),
            const SizedBox(height: 6),
            field(widget.toPhone, 'Teléfono del destinatario',
              phone: true, after: toReady ? 2 : null),
          ],
          Divider(color: _riderBorder(context), height: 13),
          header(2, 'Descripción y fotos (opcional)',
            optional ? 'Información guardada' :
              'Agregar solo si es necesario', optional),
          if (open == 2) ...[
            field(widget.description, 'Descripción del paquete'),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: widget.uploading || widget.photos >= 4
                  ? null : widget.onPhotos,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text('Tomar foto del paquete (' + widget.photos.toString() + '/4)')),
          ],
        ],
      ),
    );
  }
}

/// Two views of the original map bottom-sheet, not a separate request flow.
class _ParcelTwoPanels extends StatefulWidget {
  final Widget Function(bool details, VoidCallback forward,
      VoidCallback back) builder;
  const _ParcelTwoPanels({required this.builder});
  @override
  State<_ParcelTwoPanels> createState() => _ParcelTwoPanelsState();
}
class _ParcelTwoPanelsState extends State<_ParcelTwoPanels> {
  bool details = false;
  @override
  Widget build(BuildContext context) => widget.builder(
    details,
    () { FocusScope.of(context).unfocus(); setState(() => details = true); },
    () { FocusScope.of(context).unfocus(); setState(() => details = false); },
  );
}

/// The second panel shares the original trip/offer creation callback.
class _ParcelDetailsSecondPanel extends StatelessWidget {
  final TextEditingController senderName;
  final TextEditingController senderPhone;
  final TextEditingController recipientName;
  final TextEditingController recipientPhone;
  final TextEditingController description;
  final int photoCount;
  final bool photosUploading;
  final bool creating;
  final bool quoting;
  final bool fareReady;
  final VoidCallback onPhotos;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  const _ParcelDetailsSecondPanel({
    required this.senderName, required this.senderPhone,
    required this.recipientName, required this.recipientPhone,
    required this.description, required this.photoCount,
    required this.photosUploading, required this.creating,
    required this.quoting, required this.fareReady,
    required this.onPhotos, required this.onBack,
    required this.onCreate,
  });
  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF121212) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [BoxShadow(
          color: Color(0x26000000), blurRadius: 28,
          offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 7),
            Center(child: Container(
              width: 42, height: 4,
              decoration: BoxDecoration(
                color: _riderBorder(context),
                borderRadius: BorderRadius.circular(99)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 16, 4),
              child: Row(children: [
                IconButton(
                  onPressed: onBack,
                  icon: Icon(Icons.arrow_back_rounded,
                    color: _riderText(context)),
                  tooltip: 'Volver al precio'),
                Expanded(child: Text('Detalles de la solicitud',
                  style: TextStyle(color: _riderText(context),
                    fontSize: 19, fontWeight: FontWeight.w900))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ParcelCollapsedFields(
                    fromName: senderName, fromPhone: senderPhone,
                    toName: recipientName, toPhone: recipientPhone,
                    description: description, photos: photoCount,
                    uploading: photosUploading, onPhotos: onPhotos),
                  const SizedBox(height: 5),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                18, 10, 18, 10 + MediaQuery.viewPaddingOf(context).bottom),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF151515)
                    : const Color(0xFFFDFDFD),
                border: Border(top: BorderSide(
                  color: _riderBorder(context)))),
              child: SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: creating || quoting || photosUploading ||
                          !fareReady ? null : onCreate,
                  icon: creating
                    ? const SizedBox.square(dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.inventory_2_outlined),
                  label: const Text('Solicitar envío'),
                  style: FilledButton.styleFrom(
                    backgroundColor: expressBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                    textStyle: const TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w900))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideServiceChooserPanel extends StatelessWidget {
  final String serviceType;
  final bool parcelAvailable;
  final String? parcelKind;
  final ValueChanged<String> onParcelKind;
  final TextEditingController parcelSenderName;
  final TextEditingController parcelSenderPhone;
  final TextEditingController parcelRecipientName;
  final TextEditingController parcelRecipientPhone;
  final TextEditingController parcelDescription;
  final int parcelPhotoCount;
  final bool parcelPhotosUploading;
  final VoidCallback onAddParcelPhotos;
  final ValueChanged<String> onType;
  final List<Map<String, dynamic>> services;
  final Map<String, dynamic> settings;
  final String? zoneName;
  final String currencyCode;
  final String category;
  final String payment;
  final num fare;
  final num minimumFare;
  final bool fareReady;
  final DateTime? scheduledFor;
  final double? routeDistanceKm;
  final int? routeDurationMinutes;
  final bool routing;
  final bool quoting;
  final bool creating;
  final VoidCallback onReviewRoute;
  final VoidCallback onRetryFare;
  final ValueChanged<String> onCategory;
  final ValueChanged<num> onFare;
  final VoidCallback onEditFare;
  final VoidCallback onSchedule;
  final VoidCallback onPayment;
  final VoidCallback onCreate;

  const _RideServiceChooserPanel({
    required this.serviceType,
    required this.parcelAvailable,
    required this.parcelKind,
    required this.onParcelKind,
    required this.parcelSenderName,
    required this.parcelSenderPhone,
    required this.parcelRecipientName,
    required this.parcelRecipientPhone,
    required this.parcelDescription,
    required this.parcelPhotoCount,
    required this.parcelPhotosUploading,
    required this.onAddParcelPhotos,
    required this.onType,
    required this.services,
    required this.settings,
    required this.zoneName,
    required this.currencyCode,
    required this.category,
    required this.payment,
    required this.fare,
    required this.minimumFare,
    required this.fareReady,
    required this.scheduledFor,
    required this.routeDistanceKm,
    required this.routeDurationMinutes,
    required this.routing,
    required this.quoting,
    required this.creating,
    required this.onReviewRoute,
    required this.onRetryFare,
    required this.onCategory,
    required this.onFare,
    required this.onEditFare,
    required this.onSchedule,
    required this.onPayment,
    required this.onCreate,
  });

  Map<String, dynamic> get selectedService {
    for (final service in services) {
      if (service['service_key']?.toString() == category) return service;
    }
    return services.isNotEmpty ? services.first : _fallbackRideServices.first;
  }

  String get selectedLabel => serviceType == 'delivery'
      ? 'Envíos'
      : (selectedService['name']?.toString() ?? 'Express');

  bool get selectedAvailable => serviceType == 'delivery'
      ? parcelAvailable
      : selectedService['enabled'] != false;

  IconData get selectedIcon => serviceType == 'delivery'
      ? Icons.inventory_2_outlined
      : _rideServiceIcon(selectedService);

  int get selectedSeats => _rideServiceSeats(selectedService);

  String _durationText() {
    final minutes = routeDurationMinutes;
    return minutes == null ? 'Calculando tiempo' : minutes.toString() + ' min';
  }

  void _changeFare(double delta) {
    if (quoting || !fareReady) return;
    final clp = currencyCode.toUpperCase() == 'CLP';
    final next = (fare.toDouble() + delta)
        .clamp(minimumFare.toDouble(), 9999999.0);
    onFare(clp ? next.ceil() : double.parse(next.toStringAsFixed(2)));
  }

  @override
  Widget build(BuildContext context) {
    if (serviceType != 'delivery') return _buildChooser(context);
    return _ParcelTwoPanels(builder: (details, forward, back) =>
      details
        ? _ParcelDetailsSecondPanel(
            senderName: parcelSenderName, senderPhone: parcelSenderPhone,
            recipientName: parcelRecipientName,
            recipientPhone: parcelRecipientPhone,
            description: parcelDescription,
            photoCount: parcelPhotoCount,
            photosUploading: parcelPhotosUploading,
            creating: creating, quoting: quoting, fareReady: fareReady,
            onPhotos: onAddParcelPhotos,
            onBack: back, onCreate: onCreate)
        : _buildChooser(context, onDetails: forward));
  }

  Widget _buildChooser(BuildContext context, {VoidCallback? onDetails}) {
    final dark = _riderHomeDark(context);
    final surface = dark ? const Color(0xFF121212) : Colors.white;
    final footer = dark ? const Color(0xFF151515) : const Color(0xFFFDFDFD);

    if (services.isEmpty && !(serviceType == 'delivery' && parcelAvailable)) {
      return Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 28,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF444444)
                        : const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 22),
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0xFFFFF4E5),
                  child: Icon(
                    Icons.location_off_outlined,
                    color: Color(0xFFB54708),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Fuera de cobertura',
                  style: TextStyle(
                    color: _riderText(context),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Este punto de origen no pertenece a una zona activa de Express. Cambia el origen para ver los servicios y tarifas disponibles.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _riderMuted(context),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onReviewRoute,
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: const Text('Cambiar origen'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 28,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 7),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF444444)
                    : const Color(0xFFD0D5DD),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Padding(
                      // Reserve symmetrical room for the "Cambiar" action.
                      // Keep the title actually centered without overlap.
                      padding: const EdgeInsets.symmetric(horizontal: 76),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            serviceType == 'delivery' ? 'Elige tu envío' : 'Elige tu viaje',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _riderText(context),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (zoneName != null)
                          Text(
                            zoneName! + ' · ' + currencyCode.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _riderMuted(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onReviewRoute,
                      child: const Text('Cambiar'),
                    ),
                  ),
                ],
              ),
            ),
            if (routeDistanceKm != null &&
                routeDurationMinutes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: _RouteSummary(
                  distanceKm: routeDistanceKm!,
                  durationMinutes: routeDurationMinutes!,
                  fare: fare,
                  currencyCode: currencyCode,
                  routing: routing,
                  quoting: quoting,
                  fareReady: fareReady,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: _RideFareControlCard(
                isParcel: serviceType == 'delivery',
                icon: selectedIcon,
                title: selectedLabel,
                seats: selectedSeats,
                durationText: _durationText(),
                fare: fare,
                minimumFare: minimumFare,
                currencyCode: currencyCode,
                quoting: quoting,
                fareReady: fareReady,
                onEdit: onEditFare,
                onDecrease: fare.toDouble() <= minimumFare.toDouble() + .001
                    ? null
                    : () => _changeFare(
                  currencyCode.toUpperCase() == 'CLP' ? -100 : -0.50,
                ),
                onIncrease: () => _changeFare(
                  currencyCode.toUpperCase() == 'CLP' ? 100 : 0.50,
                ),
              ),
            ),
            if (!quoting && !fareReady)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: OutlinedButton.icon(
                  onPressed: onRetryFare,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('No se pudo calcular la tarifa · Reintentar'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Servicios', style: TextStyle(
                    color: _riderMuted(context),
                    fontSize: 11, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 7),
                  _RideServiceSlots(
                    // Same position, card widget and sizing for Taxi/Envíos.
                    // Only the names and the selection callback differ.
                    services: serviceType == 'delivery'
                        ? expressParcelVehicleCards
                        : services.where((service) =>
                            service['service_key']?.toString() != 'parcel' &&
                            service['service_key']?.toString() != 'delivery').toList(),
                    selectedKey: serviceType == 'delivery'
                        ? (parcelKind ?? '')
                        : category,
                    onSelected: serviceType == 'delivery'
                        ? onParcelKind
                        : onCategory,
                  ),
                  if (serviceType == 'delivery' && parcelKind == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Selecciona Moto, Auto o Carga para el paquete.',
                        style: TextStyle(color: _riderMuted(context), fontSize: 11)),
                    ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                18,
                10,
                18,
                10 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: footer,
                border: Border(
                  top: BorderSide(color: _riderBorder(context)),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MiniSetting(
                          icon: Icons.schedule_rounded,
                          label: 'Cuándo',
                          value: scheduledFor == null
                              ? 'Ahora'
                              : _formatSchedule(scheduledFor!),
                          onTap: onSchedule,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MiniSetting(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Pago',
                          value: _paymentLabel(payment),
                          onTap: onPayment,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: creating || quoting || !fareReady ||
                              !selectedAvailable ||
                              (serviceType == 'delivery' && parcelKind == null)
                          ? null
                          : (serviceType == 'delivery' ? onDetails : onCreate),
                      icon: creating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(serviceType == 'delivery'
                              ? Icons.inventory_2_outlined
                              : Icons.local_taxi_rounded),
                      label: Text(
                        selectedAvailable
                            ? serviceType == 'delivery'
                                ? 'Ingresar detalles'
                                : 'Confirmar viaje'
                            : 'Servicio no disponible',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: expressBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
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

class _RideServiceSlots extends StatelessWidget {
  final List<Map<String, dynamic>> services;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  const _RideServiceSlots({
    required this.services,
    required this.selectedKey,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final visible = services
        .where((service) =>
            service['passenger_visible'] != false &&
            service['service_key']?.toString().isNotEmpty == true)
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = ((constraints.maxWidth - 20) / 5)
            .clamp(72.0, 118.0)
            .toDouble();

        return Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                SizedBox(
                  width: baseWidth,
                  child: Builder(
                    builder: (context) {
                      final service = visible[i];
                      final key = service['service_key']!.toString();
                      final available = service['enabled'] != false;
                      final label = service['name']?.toString().trim();
                      return _RideServiceSlotButton(
                        label: label == null || label.isEmpty ? key : label,
                        icon: _rideServiceIcon(service),
                        available: available,
                        selected: available && selectedKey == key,
                        onTap: available ? () => onSelected(key) : null,
                      );
                    },
                  ),
                ),
                if (i != visible.length - 1) const SizedBox(width: 5),
              ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RideServiceSlotButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool available;
  final bool selected;
  final VoidCallback? onTap;

  const _RideServiceSlotButton({
    required this.label,
    required this.icon,
    required this.available,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final baseSurface =
        dark ? const Color(0xFF1B1B1B) : const Color(0xFFF7F8FA);
    final selectedSurface =
        dark ? const Color(0xFF17243A) : const Color(0xFFF1F6FF);
    final foreground = selected
        ? expressBlue
        : available
            ? _riderText(context)
            : _riderMuted(context);

    return Opacity(
      opacity: available ? 1 : .62,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 76,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? selectedSurface : baseSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? expressBlue : _riderBorder(context),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 21),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  available ? 'Disponible' : 'No disponible',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? expressBlue : _riderMuted(context),
                    fontSize: 7.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RideFareControlCard extends StatelessWidget {
  final bool isParcel;
  final IconData icon;
  final String title;
  final int seats;
  final String durationText;
  final num fare;
  final num minimumFare;
  final String currencyCode;
  final bool quoting;
  final bool fareReady;
  final VoidCallback onEdit;
  final VoidCallback? onDecrease;
  final VoidCallback onIncrease;

  const _RideFareControlCard({
    required this.isParcel,
    required this.icon,
    required this.title,
    required this.seats,
    required this.durationText,
    required this.fare,
    required this.minimumFare,
    required this.currencyCode,
    required this.quoting,
    required this.fareReady,
    required this.onEdit,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final surface = dark
        ? const Color(0xFF222222)
        : const Color(0xFFF7F8FA);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _riderBorder(context)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 42,
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF2D2D2D)
                        : const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: expressBlue, size: 26),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _riderText(context),
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            isParcel ? Icons.inventory_2_outlined
                                : Icons.person_rounded,
                            size: 14,
                            color: _riderMuted(context),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            (isParcel ? 'Paquete' : seats.toString()) +
                                ' · ' + durationText,
                            style: TextStyle(
                              color: _riderMuted(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar tarifa',
                  onPressed: quoting || !fareReady ? null : onEdit,
                  icon: Icon(
                    Icons.edit_rounded,
                    color: _riderMuted(context),
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _riderBorder(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
            child: Row(
              children: [
                _FareRoundButton(
                  icon: Icons.remove_rounded,
                  onTap: quoting || !fareReady ? null : onDecrease,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        quoting
                            ? 'Calculando…'
                            : fareReady
                                ? _rideMoney(fare, currencyCode)
                                : 'Sin tarifa',
                        style: TextStyle(
                          color: _riderText(context),
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        fareReady
                            ? 'Mínimo recomendado · ' +
                                _rideMoney(minimumFare, currencyCode)
                            : 'Esperando precio válido de tu zona',
                        style: TextStyle(
                          color: _riderMuted(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                _FareRoundButton(
                  icon: Icons.add_rounded,
                  onTap: quoting || !fareReady ? null : onIncrease,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FareRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _FareRoundButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _riderHomeDark(context)
          ? const Color(0xFF2A2A2A)
          : const Color(0xFFF0F2F5),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 48,
          child: Icon(
            icon,
            color: onTap == null
                ? _riderMuted(context)
                : _riderText(context),
            size: 25,
          ),
        ),
      ),
    );
  }
}

class _RideOfferCard extends StatelessWidget {
  final num fare;
  final String currency;
  final bool quoting;
  final VoidCallback onTap;

  const _RideOfferCard({
    required this.fare,
    required this.currency,
    required this.quoting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final border =
        dark ? const Color(0xFF383838) : const Color(0xFFE4E7EC);
    final surface =
        dark ? const Color(0xFF1D1D1D) : const Color(0xFFFFFFFF);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7FBF5),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.handshake_outlined,
                  color: Color(0xFF00A878),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pon tu precio',
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Toca para cambiar tu oferta',
                      style: TextStyle(
                        color: _riderMuted(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                quoting ? '…' : _rideMoney(fare, currency),
                style: TextStyle(
                  color: _riderText(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.edit_outlined,
                size: 17,
                color: _riderMuted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RideChoiceCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? price;
  final VoidCallback onTap;

  const _RideChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final border = selected
        ? expressBlue
        : dark
            ? const Color(0xFF353535)
            : const Color(0xFFE4E7EC);
    final surface = selected
        ? (dark ? const Color(0xFF17243A) : const Color(0xFFF3F7FF))
        : (dark ? const Color(0xFF1B1B1B) : Colors.white);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 38,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF252525)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? expressBlue
                      : _riderText(context),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _riderMuted(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (price != null)
                Text(
                  price!,
                  style: TextStyle(
                    color: _riderText(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              const SizedBox(width: 7),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? expressBlue
                    : _riderMuted(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniSetting extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _MiniSetting({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: _riderSoftSurface(context),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _riderBorder(context)),
        ),
        child: Row(
          children: [
            Icon(icon, color: expressBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: _riderMuted(context),
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      color: _riderText(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
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

class _ScheduledRideCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final VoidCallback onCancel;

  const _ScheduledRideCard({
    required this.ride,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheduled =
        DateTime.tryParse(ride['scheduled_for']?.toString() ?? '')?.toLocal();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFB8D4FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: expressBlue,
                    child: Icon(Icons.event_available_rounded, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Viaje programado',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                scheduled == null
                    ? 'Horario programado'
                    : _formatSchedule(scheduled),
                style: const TextStyle(
                  color: expressBlue,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
          (ride['pickup_address']?.toString() ?? 'Resolviendo ubicación…') +
                    ' → ' +
              (ride['destination_address']?.toString() ??
                  'Resolviendo ubicación…'),
                style: const TextStyle(color: expressMuted),
              ),
              const SizedBox(height: 8),
              const Text(
                'La búsqueda de conductores se activará cuando se acerque la hora.',
                style: TextStyle(color: expressMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancelar viaje programado'),
          ),
        ),
      ],
    );
  }
}

class _RadarPulse extends StatefulWidget {
  const _RadarPulse();

  @override
  State<_RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<_RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 66,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Builder(
                  builder: (context) {
                    final progress = (controller.value + i / 3) % 1.0;
                    final opacity =
                        (1.0 - progress).clamp(0.0, 1.0).toDouble();
                    return Transform.scale(
                      scale: .55 + progress * .70,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: expressBlue.withValues(alpha: opacity * .42),
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: expressBlue,
                  size: 22,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchFareDialog extends StatefulWidget {
  final num initialFare;
  final String currency;
  final num step;

  const _SearchFareDialog({
    required this.initialFare,
    required this.currency,
    required this.step,
  });

  @override
  State<_SearchFareDialog> createState() => _SearchFareDialogState();
}

class _SearchFareDialogState extends State<_SearchFareDialog> {
  // La oferta confirmada al abrir el panel es el piso: no se puede bajar de ella.
  late num offer = widget.initialFare;
  late final num step = widget.step;
  String? message;

  bool get _canDecrease => offer - step >= widget.initialFare;

  void _change(num delta) {
    final next = offer + delta;
    if (next < widget.initialFare) {
      setState(() => message = 'No puedes bajar de la oferta confirmada.');
      return;
    }
    setState(() {
      offer = next;
      message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Ajusta tu oferta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Bajar',
                onPressed: _canDecrease ? () => _change(-step) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _rideMoney(offer, widget.currency),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Subir',
                onPressed: () => _change(step),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Cada ajuste es ${_rideMoney(step, widget.currency)}.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: offer > widget.initialFare
              ? () => Navigator.pop(context, offer)
              : null,
          child: const Text('Buscar 3 min más'),
        ),
      ],
    );
  }
}

class _SearchRoundDecisionDialog extends StatefulWidget {
  final double currentFare;
  final String currency;
  final bool isParcel;

  const _SearchRoundDecisionDialog({
    required this.currentFare,
    required this.currency,
    this.isParcel = false,
  });

  @override
  State<_SearchRoundDecisionDialog> createState() =>
      _SearchRoundDecisionDialogState();
}

class _SearchRoundDecisionDialogState
    extends State<_SearchRoundDecisionDialog> {
  Timer? timer;
  int remaining = 30;
  late final DateTime expiresAt;

  @override
  void initState() {
    super.initState();
    expiresAt = DateTime.now().toUtc().add(const Duration(seconds: 30));
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = expiresAt
          .difference(DateTime.now().toUtc())
          .inSeconds
          .clamp(0, 30)
          .toInt();
      if (next <= 0) {
        timer?.cancel();
        Navigator.pop(context, 'cancel');
        return;
      }
      if (next != remaining) {
        setState(() => remaining = next);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpressJourneyDialog(
      icon: Icons.radar_rounded,
      title: '¿Seguimos buscando?',
      subtitle: 'Seguimos buscando un conductor para tu '
          '${widget.isParcel ? 'envío' : 'viaje'}. '
          'Puedes ampliar la búsqueda por 3 minutos, mejorar tu oferta '
          'o cancelar.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0B57D0).withValues(alpha: .08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF0B57D0).withValues(alpha: .16),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'TU OFERTA ACTUAL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _rideMoney(widget.currentFare, widget.currency),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.timer_outlined, color: scheme.onSurfaceVariant, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Se cancelará automáticamente en $remaining s',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: remaining / 30,
              minHeight: 5,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, 'continue'),
          icon: const Icon(Icons.search_rounded),
          label: const Text('Seguir buscando 3 min'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, 'raise'),
          icon: const Icon(Icons.trending_up_rounded),
          label: const Text('Subir mi oferta'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('Cancelar búsqueda'),
        ),
      ],
    );

  }
}


class _PassengerSearchStatusCard extends StatefulWidget {
  final Map<String, dynamic> ride;
  final int viewedCount;
  final List<Map<String, dynamic>> viewers;
  final int nearbyCount;
  final bool autoAcceptNearest;
  final ValueChanged<bool> onAutoAcceptNearest;
  final VoidCallback onCancel;

  const _PassengerSearchStatusCard({
    required this.ride,
    required this.viewedCount,
    required this.viewers,
    required this.nearbyCount,
    required this.autoAcceptNearest,
    required this.onAutoAcceptNearest,
    required this.onCancel,
  });

  @override
  State<_PassengerSearchStatusCard> createState() =>
      _PassengerSearchStatusCardState();
}

class _PassengerSearchStatusCardState
    extends State<_PassengerSearchStatusCard> {
  Timer? timer;
  DateTime now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now().toUtc());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt =
        DateTime.tryParse(widget.ride['expires_at']?.toString() ?? '')?.toUtc();
    final remaining = expiresAt == null
        ? 0
        : expiresAt.difference(now).inSeconds.clamp(0, 9999);
    const total = 180;
    final elapsed = (total - remaining).clamp(0, total);
    final progress = (remaining / total).clamp(0.0, 1.0).toDouble();

    String title;
    String subtitle;
    if (elapsed < 36) {
      title = 'Ofreciendo tu tarifa';
      subtitle = widget.nearbyCount > 0
          ? '${widget.nearbyCount} conductores están cerca'
          : 'Esperando que un conductor responda';
    } else if (elapsed < 55) {
      title = 'Esperando respuestas';
      subtitle = 'Tú eliges al conductor que prefieras';
    } else {
      title = 'Buscando más opciones';
      subtitle = 'Ampliando el área de búsqueda';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.viewedCount > 0) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.viewedCount} ${widget.viewedCount == 1 ? 'conductor está viendo' : 'conductores están viendo'} tu solicitud',
                  style: TextStyle(
                    color: _riderText(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _DriverViewerStack(
                viewers: widget.viewers,
                total: widget.viewedCount,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            color: _riderSoftSurface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _riderBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: expressBlue.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      color: expressBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: _riderText(context),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: _riderMuted(context),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (remaining > 0)
                    Text(
                      '${(remaining ~/ 60).toString()}:${(remaining % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: _riderBorder(context),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(expressBlue),
                ),
              ),
              if (widget.nearbyCount > 0) ...[
                const SizedBox(height: 7),
                Text(
                  '${widget.nearbyCount} ${widget.nearbyCount == 1 ? 'vehículo disponible' : 'vehículos disponibles'} cerca',
                  style: const TextStyle(
                    color: expressBlue,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: _riderSoftSurface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _riderBorder(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aceptar automáticamente al más cercano',
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Se elegirá la oferta con menor tiempo de llegada.',
                      style: TextStyle(
                        color: _riderMuted(context),
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: widget.autoAcceptNearest,
                onChanged: widget.onAutoAcceptNearest,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancelar búsqueda'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD92D20),
              side: BorderSide(
                color: const Color(0xFFD92D20).withValues(alpha: .55),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PresentedPassengerOffer {
  final String presentationKey;
  final String offerId;
  final Map<String, dynamic> offer;
  DateTime? visibleUntil;

  _PresentedPassengerOffer({
    required this.presentationKey,
    required this.offerId,
    required this.offer,
  });
}

class _OffersCard extends StatefulWidget {
  final Map<String, dynamic> ride;
  final List<Map<String, dynamic>> offers;
  final int viewedCount;
  final List<Map<String, dynamic>> viewers;
  final int nearbyCount;
  final bool autoAcceptNearest;
  final ValueChanged<bool> onAutoAcceptNearest;
  final ValueChanged<Map<String, dynamic>> onOffer;
  final ValueChanged<Map<String, dynamic>> onDecline;
  final ValueChanged<Map<String, dynamic>> onExpire;
  final VoidCallback onCancel;

  const _OffersCard({
    super.key,
    required this.ride,
    required this.offers,
    required this.viewedCount,
    required this.viewers,
    required this.nearbyCount,
    required this.autoAcceptNearest,
    required this.onAutoAcceptNearest,
    required this.onOffer,
    required this.onDecline,
    required this.onExpire,
    required this.onCancel,
  });

  @override
  State<_OffersCard> createState() => _OffersCardState();
}

class _OffersCardState extends State<_OffersCard> {
  static const int _maxVisibleOffers = 3;
  Timer? timer;
  DateTime now = DateTime.now().toUtc();
  final List<_PresentedPassengerOffer> visibleOffers = [];
  final List<_PresentedPassengerOffer> queuedOffers = [];
  final Set<String> seenOfferKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _syncOfferQueue();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final tick = DateTime.now().toUtc();
      final expired = visibleOffers
          .where((item) =>
              item.visibleUntil != null &&
              !item.visibleUntil!.isAfter(tick))
          .toList();

      if (expired.isNotEmpty) {
        visibleOffers.removeWhere(expired.contains);
        for (final item in expired) {
          final hasNewerPresentation =
              visibleOffers.any((other) => other.offerId == item.offerId) ||
                  queuedOffers.any((other) => other.offerId == item.offerId);
          if (!hasNewerPresentation) {
            widget.onExpire(item.offer);
          }
        }
        _fillVisibleSlots(tick);
      }

      setState(() => now = tick);
    });
  }

  @override
  void didUpdateWidget(covariant _OffersCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOfferQueue();
  }

  String _presentationKey(Map<String, dynamic> offer) {
    return (offer['id']?.toString() ?? '') +
        ':' +
        (offer['created_at']?.toString() ?? '') +
        ':' +
        (offer['proposed_fare']?.toString() ?? '');
  }

  void _syncOfferQueue() {
    final activeIds = widget.offers
        .map((offer) => offer['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    visibleOffers.removeWhere((item) => !activeIds.contains(item.offerId));
    queuedOffers.removeWhere((item) => !activeIds.contains(item.offerId));

    final incoming = List<Map<String, dynamic>>.from(widget.offers)
      ..sort((a, b) {
        final aTime =
            DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });

    var added = false;
    for (final offer in incoming) {
      final id = offer['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final key = _presentationKey(offer);
      if (seenOfferKeys.contains(key)) {
        // Realtime can deliver a bare offer before the secure RPC supplies
        // driver_profiles.profile_photo_path. Refresh the existing visible
        // presentation instead of keeping its initial incomplete snapshot.
        for (final item in [...visibleOffers, ...queuedOffers]) {
          if (item.presentationKey == key) {
            final merged = refreshedPassengerOffer(item.offer, offer);
            item.offer
              ..clear()
              ..addAll(merged);
            break;
          }
        }
        continue;
      }

      // Una reoferta del mismo conductor conserva la presentación anterior
      // y entra debajo como una nueva versión. El backend reutiliza el mismo
      // id por conductor, por eso la clave de presentación incluye fecha/monto.
      seenOfferKeys.add(key);
      queuedOffers.add(
        _PresentedPassengerOffer(
          presentationKey: key,
          offerId: id,
          offer: Map<String, dynamic>.from(offer),
        ),
      );
      added = true;
    }

    _fillVisibleSlots(DateTime.now().toUtc());
    if (added) {
      startExpressAlertSound(durationSeconds: 5);
    }
  }

  void _fillVisibleSlots(DateTime startedAt) {
    while (visibleOffers.length < _maxVisibleOffers &&
        queuedOffers.isNotEmpty) {
      final item = queuedOffers.removeAt(0);
      final createdAt =
          DateTime.tryParse(item.offer['created_at']?.toString() ?? '')
              ?.toUtc();
      final serverExpiresAt =
          DateTime.tryParse(item.offer['expires_at']?.toString() ?? '')
              ?.toUtc();

      // El servidor define el vencimiento. 30 s es solo el fallback para
      // respuestas antiguas sin expires_at.
      final deadline = serverExpiresAt ??
          (createdAt ?? startedAt).add(const Duration(seconds: 30));

      item.visibleUntil = deadline;
      if (deadline.isAfter(startedAt)) {
        visibleOffers.add(item);
      } else {
        widget.onExpire(item.offer);
      }
    }
  }

  int _remainingSeconds(_PresentedPassengerOffer item) {
    final until = item.visibleUntil;
    if (until == null) return 30;
    return until.difference(now).inSeconds.clamp(0, 30).toInt();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt =
        DateTime.tryParse(widget.ride['expires_at']?.toString() ?? '')?.toUtc();
    final remaining = expiresAt == null
        ? 0
        : expiresAt.difference(now).inSeconds.clamp(0, 9999);
    const total = 180;
    final elapsed = (total - remaining).clamp(0, total);
    final progress =
        (remaining / total).clamp(0.0, 1.0).toDouble();

    String title;
    String subtitle;
    if (elapsed < 36) {
      title = 'Ofreciendo tu tarifa';
      subtitle = widget.nearbyCount > 0
          ? '${widget.nearbyCount} conductores están cerca'
          : 'Esperando que un conductor responda';
    } else if (elapsed < 55) {
      title = 'Esperando respuestas';
      subtitle = 'Tú eliges al conductor que prefieras';
    } else {
      title = 'Buscando más opciones';
      subtitle = 'Ampliando el área de búsqueda';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (visibleOffers.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 22),
              label: const Text('Cancelar solicitud'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Elige a un conductor',
            style: TextStyle(
              color: _riderText(context),
              fontSize: 24,
              fontWeight: FontWeight.w900,
              shadows: const [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(
                Icons.verified_user_rounded,
                color: expressBlue,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Todos los conductores están verificados',
                  style: TextStyle(
                    color: _riderText(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 7,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in visibleOffers) ...[
            _PassengerDriverOfferCard(
              offer: item.offer,
              currency: widget.ride['currency']?.toString() ?? 'BOB',
              remainingSeconds: _remainingSeconds(item),
              passengerFare: asDouble(widget.ride['proposed_fare']),
              onAccept: () => widget.onOffer(item.offer),
              onReject: () => widget.onDecline(item.offer),
            ),
            const SizedBox(height: 10),
          ],
        ] else ...[
        if (widget.viewedCount > 0) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.viewedCount} ${widget.viewedCount == 1 ? 'conductor está viendo' : 'conductores están viendo'} tu solicitud',
                  style: TextStyle(
                    color: _riderText(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _DriverViewerStack(
                viewers: widget.viewers,
                total: widget.viewedCount,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            color: _riderSoftSurface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _riderBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: expressBlue.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      color: expressBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: _riderText(context),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: _riderMuted(context),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (remaining > 0)
                    Text(
                      '${(remaining ~/ 60).toString()}:${(remaining % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
              ...[
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: _riderBorder(context),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(expressBlue),
                  ),
                ),
              ],
              if (widget.nearbyCount > 0) ...[
                const SizedBox(height: 7),
                Text(
                  '${widget.nearbyCount} ${widget.nearbyCount == 1 ? 'vehículo disponible' : 'vehículos disponibles'} cerca',
                  style: const TextStyle(
                    color: expressBlue,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: _riderSoftSurface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _riderBorder(context)),
          ),
          child: SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: widget.autoAcceptNearest,
            onChanged: widget.onAutoAcceptNearest,
            title: Text(
              'Aceptar automáticamente al más cercano',
              style: TextStyle(
                color: _riderText(context),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              'Se elegirá la oferta con menor tiempo de llegada.',
              style: TextStyle(
                color: _riderMuted(context),
                fontSize: 9.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancelar búsqueda'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD92D20),
              side: BorderSide(
                color: const Color(0xFFD92D20).withValues(alpha: .55),
              ),
            ),
          ),
        ),
        ],
      ],
    );
  }
}


class _PassengerDriverOfferCard extends StatelessWidget {
  final Map<String, dynamic> offer;
  final String currency;
  final int remainingSeconds;
  final double? passengerFare;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _PassengerDriverOfferCard({
    required this.offer,
    required this.currency,
    required this.remainingSeconds,
    required this.passengerFare,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final user = offer['driver_user'] is Map
        ? Map<String, dynamic>.from(offer['driver_user'] as Map)
        : <String, dynamic>{};
    final profile = offer['driver_profiles'] is Map
        ? Map<String, dynamic>.from(offer['driver_profiles'] as Map)
        : <String, dynamic>{};

    final name = user['full_name']?.toString().trim();
    final avatar = user['avatar_url']?.toString().trim();
    final fare = asDouble(offer['proposed_fare']) ?? 0;
    final eta = (offer['eta_minutes'] as num?)?.toInt();
    final rating = asDouble(profile['rating']);
    final completedTrips =
        (profile['completed_trips'] as num?)?.toInt() ?? 0;
    final vehicle = profile['vehicle_summary']?.toString().trim();
    final matchesPassengerFare =
        passengerFare != null && (fare - passengerFare!).abs() < .01;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: _riderSoftSurface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _riderBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _rideMoney(fare, currency),
                style: TextStyle(
                  color: _riderText(context),
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (eta != null) ...[
                const SizedBox(width: 8),
                Text(
                  '$eta min',
                  style: TextStyle(
                    color: _riderText(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${remainingSeconds.clamp(0, 30)} s',
                    style: const TextStyle(
                      color: expressBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (matchesPassengerFare)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: expressBlue.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'Tu tarifa',
                        style: TextStyle(
                          color: expressBlue,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              _OfferDriverPortrait(
                driverId: offer['driver_id']?.toString(),
                approvedPath: authorizedOfferPortraitPath(offer),
                fallbackUrl: avatar,
              ),
              const SizedBox(width: 10),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (rating == null
                              ? '★ 5.0'
                              : '★ ${rating.toStringAsFixed(2)}') +
                          (completedTrips > 0
                              ? ' · $completedTrips viajes'
                              : ''),
                      style: TextStyle(
                        color: _riderMuted(context),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (vehicle != null && vehicle.isNotEmpty)
                      Text(
                        vehicle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _riderMuted(context),
                          fontSize: 10.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: remainingSeconds.clamp(0, 30) / 30,
              minHeight: 3,
              backgroundColor: _riderBorder(context),
              valueColor: const AlwaysStoppedAnimation<Color>(expressBlue),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _riderText(context),
                    minimumSize: const Size(0, 43),
                  ),
                  child: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: expressBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 43),
                  ),
                  child: const Text('Aceptar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverViewerStack extends StatelessWidget {
  final List<Map<String, dynamic>> viewers;
  final int total;

  const _DriverViewerStack({
    required this.viewers,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final visible = viewers.take(4).toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();
    const size = 27.0;
    const overlap = 9.0;
    final extra = total - visible.length;
    final width = size + (visible.length - 1) * (size - overlap) +
        (extra > 0 ? size - overlap : 0);

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: _DriverViewerAvatar(
                viewer: visible[i],
                size: size,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: visible.length * (size - overlap),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _riderSoftSurface(context),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _riderSurface(context),
                    width: 2,
                  ),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    color: _riderText(context),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Share the same authorized, in-memory portrait with passengers and drivers.
class _PrivateDriverPortrait extends StatelessWidget {
  final String? driverId;
  final String? path;
  final String? fallbackUrl;
  final double radius = 25;
  const _PrivateDriverPortrait({
    this.driverId, required this.path, required this.fallbackUrl,

  });
  @override
  Widget build(BuildContext context) => ExpressDriverPortrait(
    key: ValueKey(driverId ?? path ?? 'no-driver'),
    driverId: driverId, approvedPath: path,
    fallbackUrl: fallbackUrl, radius: radius,
  );
}

class _OfferDriverPortrait extends StatelessWidget {
  final String? driverId;
  final String? approvedPath;
  final String? fallbackUrl;
  final double radius;
  const _OfferDriverPortrait({
    required this.driverId,
    required this.approvedPath,
    required this.fallbackUrl,
    this.radius = 21,
  });
  @override
  Widget build(BuildContext context) => ExpressDriverPortrait(
    key: ValueKey(driverId ?? 'no-driver'),
    driverId: driverId, approvedPath: approvedPath,
    fallbackUrl: fallbackUrl, radius: radius,
  );
}

class _DriverViewerAvatar extends StatelessWidget {
  final Map<String, dynamic> viewer;
  final double size;

  const _DriverViewerAvatar({
    required this.viewer,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final name = viewer['full_name']?.toString().trim() ?? '';
    final avatar = viewer['avatar_url']?.toString().trim() ?? '';
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    Widget fallback() => Container(
          color: expressBlue,
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _riderSurface(context),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(
        child: avatar.isEmpty
            ? fallback()
            : Image.network(
                avatar,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback(),
              ),
      ),
    );
  }
}

class _ExpiringRideOfferCard extends StatefulWidget {
  final Map<String, dynamic> offer;
  final VoidCallback onChoose;
  final VoidCallback onDecline;

  const _ExpiringRideOfferCard({
    required this.offer,
    required this.onChoose,
    required this.onDecline,
  });

  @override
  State<_ExpiringRideOfferCard> createState() =>
      _ExpiringRideOfferCardState();
}

class _ExpiringRideOfferCardState extends State<_ExpiringRideOfferCard> {
  Timer? timer;
  int remaining = 20;

  @override
  void initState() {
    super.initState();
    _syncRemaining();
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _syncRemaining(),
    );
  }

  @override
  void didUpdateWidget(covariant _ExpiringRideOfferCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer['expires_at'] != widget.offer['expires_at']) {
      _syncRemaining();
    }
  }

  void _syncRemaining() {
    final expiresAt = DateTime.tryParse(
      widget.offer['expires_at']?.toString() ?? '',
    )?.toUtc();
    final next = expiresAt == null
        ? 30
        : expiresAt.difference(DateTime.now().toUtc()).inSeconds;
    if (!mounted) return;
    setState(() => remaining = next.clamp(0, 30).toInt());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (remaining <= 0) return const SizedBox.shrink();

    final rawDriver = widget.offer['driver_profiles'];
    final driver = rawDriver is Map
        ? Map<String, dynamic>.from(rawDriver)
        : <String, dynamic>{};
    final rawUser = widget.offer['driver_user'];
    final driverUser = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
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
      fallback: 'Resolviendo ubicación…',
    );
    final destination = _expressDriverRouteLabel(
      ride,
      addressKey: 'destination_address',
      latitudeKey: 'destination_latitude',
      longitudeKey: 'destination_longitude',
      fallback: 'Resolviendo ubicación…',
    );
    final fare = asDouble(trip['final_fare']) ??
        asDouble(ride['proposed_fare']);
    final passengerDue = asDouble(trip['passenger_due_amount']);
    final promotionCredit = asDouble(trip['promotion_credit_amount']) ?? 0;
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
                  _rideMoney(passengerDue ?? fare, currency),
                  style: const TextStyle(
                    color: expressBlue,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          if (promotionCredit > 0 && passengerDue != null) ...[
            const SizedBox(height: 4),
            Text(
              'Cobrar ${_rideMoney(passengerDue, currency)} · ${_rideMoney(promotionCredit, currency)} acreditados en billetera',
              style: TextStyle(color: _riderMuted(context), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
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

class _PassengerActiveTripCard extends StatefulWidget {
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

  @override
  State<_PassengerActiveTripCard> createState() => _PassengerActiveTripCardState();
}

class _PassengerActiveTripCardState extends State<_PassengerActiveTripCard> {
  Map<String, dynamic>? partnerIdentity;
  Map<String, dynamic> get trip => widget.trip;
  Map<String, dynamic>? get driver => widget.driver;
  Map<String, dynamic>? get driverProfile => widget.driverProfile;
  Map<String, dynamic>? get vehicle => widget.vehicle;

  @override
  void initState() {
    super.initState();
    _loadPartnerIdentity();
  }

  @override
  void didUpdateWidget(covariant _PassengerActiveTripCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trip['driver_id'] != widget.trip['driver_id']) {
      partnerIdentity = null;
      _loadPartnerIdentity();
    }
  }

  Future<void> _loadPartnerIdentity() async {
    final driverId = widget.trip['driver_id']?.toString();
    if (driverId == null || driverId.isEmpty) return;
    try {
      final raw = await supabase.rpc(
        'driver_partner_public_identity',
        params: {
          'p_trip_id': widget.trip['id'],
          'p_driver_id': driverId,
        },
      );
      if (!mounted || raw is! Map) return;
      setState(() => partnerIdentity = Map<String, dynamic>.from(raw));
    } catch (_) {
      // The trip card remains usable if the driver has no syndicate identity.
    }
  }

  int? _etaMinutes() {
    final trip = widget.trip;
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
    final trip = widget.trip;
    final driver = widget.driver;
    final driverProfile = widget.driverProfile;
    final vehicle = widget.vehicle;
    final adSettings = widget.adSettings;
    final onMap = widget.onMap;
    final onChat = widget.onChat;
    final onCall = widget.onCall;
    final onShare = widget.onShare;
    final onEmergency = widget.onEmergency;
    final onPassengerOnWay = widget.onPassengerOnWay;
    final onCancel = widget.onCancel;
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
    final fareRide = trip['ride_requests'] is Map
        ? Map<String, dynamic>.from(trip['ride_requests'] as Map)
        : <String, dynamic>{};
    final fare = asDouble(trip['final_fare']) ??
        asDouble(fareRide['proposed_fare']);
    final passengerDue = asDouble(trip['passenger_due_amount']);
    final promotionCredit = asDouble(trip['promotion_credit_amount']) ?? 0;
    final currency = fareRide['currency']?.toString() ??
        trip['currency']?.toString() ?? 'BOB';
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
          if (fare != null && fare > 0) ...[
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
                border: Border.all(color: expressBlue.withValues(alpha: .20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: expressBlue),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      passengerDue != null ? 'Pagas al conductor' : 'Tarifa del viaje',
                      style: TextStyle(
                        color: _riderText(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    _rideMoney(passengerDue ?? fare, currency),
                    style: const TextStyle(
                      color: expressBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (promotionCredit > 0)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  'Express cubre ${_rideMoney(promotionCredit, currency)} y lo acredita en la billetera del conductor.',
                  style: TextStyle(color: _riderMuted(context), fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
          ],
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
                      if (partnerIdentity != null) ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            if ((partnerIdentity!['logo_url'] ?? '')
                                .toString().isNotEmpty)
                              CircleAvatar(
                                radius: 11,
                                backgroundImage: NetworkImage(
                                  partnerIdentity!['logo_url'].toString(),
                                ),
                              )
                            else
                              const Icon(Icons.groups_2_rounded,
                                  size: 18, color: expressBlue),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                partnerIdentity!['partner_name']?.toString() ??
                                    'Sindicato',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _riderText(context),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (partnerIdentity!['member_number'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Color(int.parse(
                                        (partnerIdentity!['brand_color'] ??
                                                '#ED6B1F')
                                            .toString()
                                            .replaceFirst('#', ''),
                                        radix: 16,
                                      ) |
                                      0xFF000000),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'SOCIOS ${partnerIdentity!['member_number']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
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
                  icon: Icons.navigation_rounded,
                  label: 'Waze',
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

String? _driverDeliveryNextLabel(
  String? status, {
  bool restaurantOrder = false,
}) {
  switch (status) {
    case 'accepted':
      return restaurantOrder ? 'Pedido recogido' : 'Paquete recogido';
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

String _deliveryStatus(String? value, {bool restaurantOrder = false}) {
  switch (value) {
    case 'accepted':
      return 'Repartidor asignado';
    case 'picked_up':
      return restaurantOrder ? 'Pedido recogido' : 'Paquete recogido';
    case 'in_transit':
      return 'En camino';
    default:
      return value ?? (restaurantOrder ? 'Pedido activo' : 'Delivery activo');
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

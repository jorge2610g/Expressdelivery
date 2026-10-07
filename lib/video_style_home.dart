import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_error_reporter.dart';
import 'core/supabase_client.dart';
import 'connected_center.dart';
import 'driver_priority_page.dart';
import 'express_marketplace_page.dart';
import 'express_branding.dart';
import 'location_picker.dart';
import 'location_service.dart';
import 'map_provider.dart';
import 'push_notifications.dart';
import 'preview_diagnostics_hub.dart';
import 'private_voice_call.dart';
import 'passenger_ads.dart';
import 'service_tracking.dart';
import 'services/express_service.dart';

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

    return Material(
      color: const Color(0x52000000),
      child: Center(
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
    'Viaje: ${trip['id']}.',
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
          'No se pudo abrir WhatsApp. Los datos del viaje se copiaron.',
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
  int score = 5;
  final comment = TextEditingController();
  final kind = pending['kind']?.toString() ?? 'trip';
  final toUserId = pending['to_user_id']?.toString();
  if (toUserId == null || toUserId.isEmpty) return false;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocalState) => AlertDialog(
        title: Text(
          kind == 'delivery'
              ? 'Califica al $counterpartLabel'
              : 'Califica al $counterpartLabel',
        ),
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
                    onPressed: () => setLocalState(() => score = value),
                    icon: Icon(
                      value <= score
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
                controller: comment,
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
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Después'),
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                await service.submitRating(
                  tripId: kind == 'trip' ? pending['id']?.toString() : null,
                  deliveryId:
                      kind == 'delivery' ? pending['id']?.toString() : null,
                  toUserId: toUserId,
                  score: score,
                  comment: comment.text.trim().isEmpty
                      ? null
                      : comment.text.trim(),
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'No se pudo guardar la calificación: ' + e.toString(),
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.star_rounded),
            label: const Text('Enviar calificación'),
          ),
        ],
      ),
    ),
  );

  comment.dispose();
  return saved == true;
}

double _routeConfirmationSheetFraction(BuildContext context) {
  final media = MediaQuery.of(context);
  final height = media.size.height;
  if (height <= 0) return .42;

  final usesGestureNavigation = media.systemGestureInsets.bottom > 0;
  final classicNavigationInset = usesGestureNavigation
      ? 0.0
      : media.viewPadding.bottom.clamp(0.0, 56.0).toDouble();

  // Keep the confirmation sheet close to its real content height.
  // Classic Android 3-button navigation receives extra room; gesture
  // navigation and web stay visually tighter to the bottom edge.
  final desiredHeight = 350.0 + classicNavigationInset;
  return (desiredHeight / height).clamp(.34, .50).toDouble();
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
  final String initialServiceType;
  final VoidCallback onChanged;
  final VoidCallback onHardReset;
  final VoidCallback onSwitchMode;
  final VoidCallback onOpenMarket;
  final VoidCallback onHistory;
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
    this.initialServiceType = 'ride',
    required this.onChanged,
    required this.onHardReset,
    required this.onSwitchMode,
    required this.onOpenMarket,
    required this.onHistory,
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
  final mapController = MapController();
  final sheetController = DraggableScrollableController();
  final locationService = const ExpressLocationService();

  LatLng? current;
  PickedLocation? pickup;
  PickedLocation? destination;
  String serviceType = 'ride';
  String category = 'motorcycle';
  String payment = 'cash';
  bool paymentInitializedFromProfile = false;
  num fare = 5;
  Map<String, dynamic> fareQuote = const <String, dynamic>{};
  List<Map<String, dynamic>> rideServices = _fallbackRideServices;
  Map<String, dynamic> runtimeSettings = const <String, dynamic>{};
  Map<String, dynamic>? activeZone;
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
    super.initState();
    serviceType = widget.initialServiceType == 'delivery' ? 'delivery' : 'ride';
    WidgetsBinding.instance.addObserver(this);

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

      final visibleServices = rows
          .where((row) =>
              row['passenger_visible'] != false &&
              row['service_key']?.toString() != 'delivery')
          .toList();
      if (!mounted) return;

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
        runtimeSettings = effectiveSettings;
        activeZone = zone;
        zoneOutsideCoverage = outsideCoverage;
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

      PreviewDiagnosticsHub.note(
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
              second[index]['status']?.toString()) {
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
          activeTrip: liveTrip,
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
      if (PreviewDiagnosticsHub.passengerUi.value.uiOfferCount == 0) {
        PreviewDiagnosticsHub.note('OFFER_UI_HARD_REFRESH');
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
      PreviewDiagnosticsHub.note('FOREGROUND_PUSH_RIDE_OFFER');
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

        PreviewDiagnosticsHub.note(
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
        PreviewDiagnosticsHub.note(
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

    PreviewDiagnosticsHub.note(
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
      } catch (_) {
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

    if (identical(openRide, source.openRide) &&
        identical(activeTrip, source.activeTrip) &&
        identical(activeDelivery, source.activeDelivery)) {
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
      pendingRating: source.pendingRating,
      viewedCount: openRide == null ? 0 : source.viewedCount,
      viewers: openRide == null ? const [] : source.viewers,
      nearbyDrivers: source.nearbyDrivers,
    );
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
      mapController.move(LatLng(lat, lng), 14.6);
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
          padding: EdgeInsets.fromLTRB(
            46,
            104,
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
      mapController.move(point, passengerMapZoom);
    }

    // Al salir del flujo descartamos cualquier origen manual anterior y
    // pedimos una posición GPS nueva para que el siguiente viaje empiece desde
    // la ubicación real del pasajero.
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
          final shouldResetPickup = pickup == null;
          setState(() {
            current = cachedPoint;
            if (shouldResetPickup) {
              pickup = PickedLocation(
                label: 'Mi ubicación actual',
                latitude: cached.latitude,
                longitude: cached.longitude,
              );
            }
          });
          passengerMapZoom = 14.6;
          mapController.move(cachedPoint!, passengerMapZoom);
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
              fromLatitude: cachedPoint!.latitude,
              fromLongitude: cachedPoint!.longitude,
              toLatitude: position.latitude,
              toLongitude: position.longitude,
            );
      final shouldResetPickup = resetPickupToGps || pickup == null;
      setState(() {
        current = point;
        if (shouldResetPickup) {
          pickup = PickedLocation(
            label: 'Mi ubicación actual',
            latitude: position.latitude,
            longitude: position.longitude,
          );
        }
      });

      passengerMapZoom = 14.6;
      mapController.move(point, passengerMapZoom);

      // Do not re-query zone/services for tiny GPS corrections.
      if (resetPickupToGps || cachedPoint == null || movedMeters >= 200) {
        await _loadRideServices(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      // Si el usuario pulsa el botón de centrar después de haber elegido un
      // origen manual, el GPS vuelve a ser el origen del viaje y la ruta se
      // recalcula con ese punto real.
      if (resetPickupToGps && destination != null) {
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
          title: '¿A dónde vas?',
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
      roadRoute = [from, to];
    });

    try {
      final route = await ExpressMapProvider.drivingRoute(
        from: from,
        to: to,
      );

      if (mounted) {
        setState(() {
          roadRoute = route.points.length >= 2 ? route.points : <LatLng>[from, to];
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
      // Mantener la línea directa si Mapbox y el respaldo no responden.
    } finally {
      if (mounted) {
        setState(() => routing = false);
        if (routeConfirmed) {
          await _refreshFareQuote();
        }
      }
    }
  }

  Future<void> _confirmRoute() async {
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
                        'Uno de los puntos del viaje está dentro de una zona marcada por administración.',
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

    setState(() => routeConfirmed = true);
    final chooserFraction = _rideChooserSheetFraction(context);
    _movePassengerSheet(chooserFraction);
    _fitRouteCamera(panelFraction: chooserFraction);
    await _refreshFareQuote();
  }

  Future<void> _refreshFareQuote() async {
    final distance = routeDistanceKm;
    final duration = routeDurationMinutes;
    final origin = pickup;
    if (destination == null || distance == null || duration == null) return;

    setState(() => quoting = true);
    try {
      final quote = origin == null
          ? await widget.service.quoteFare(
              serviceKey: category,
              distanceKm: distance,
              durationMinutes: duration,
              previewDemand: expressPreviewDemandMode,
            )
          : await widget.service.quoteServiceFareForLocation(
              serviceKey: category,
              distanceKm: distance,
              durationMinutes: duration,
              latitude: origin.latitude,
              longitude: origin.longitude,
            );

      final recommended = asDouble(quote['minimum_allowed_fare']) ??
          asDouble(quote['recommended_fare']) ??
          asDouble(quote['amount']);
      if (!mounted || recommended == null || recommended <= 0) return;

      setState(() {
        fareQuote = Map<String, dynamic>.from(quote);
        // Conservamos cualquier mejora voluntaria del pasajero. Si la demanda
        // cambió y elevó el mínimo, subimos la oferta al nuevo piso.
        if (!fareManuallyEdited || fare.toDouble() < recommended) {
          fare = recommended;
        }
      });
    } catch (_) {
      // El backend vuelve a comprobar el piso al crear la solicitud.
    } finally {
      if (mounted) setState(() => quoting = false);
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
    var activeTrip = rawActiveTrip;
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
        requestedVehicleType = widget.service.runtimeChannel == 'preview'
            ? null
            : configuredVehicle == 'any'
                ? null
                : configuredVehicle ??
                    (effectiveCategory == 'motorcycle'
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
        expiresAt.isAfter(DateTime.now().toUtc()) ||
        renewalPromptedRideIds.contains(id)) {
      return;
    }

    renewalPromptedRideIds.add(id);
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
      ),
    );

    if (!mounted) return;
    renewalDecisionOpen = false;
    renewalDecisionRideId = null;

    if (result == 'continue') {
      try {
        await widget.service.renewRideRequest(id);
        renewalPromptedRideIds.remove(id);
        if (mounted) _refreshHome();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo continuar la búsqueda: $e')),
        );
      }
      return;
    }

    if (result == 'raise') {
      final newFare = await _askSearchFare(
        asDouble(ride['proposed_fare']) ?? fare.toDouble(),
      );
      if (!mounted) return;
      if (newFare != null) {
        try {
          await widget.service.renewRideRequest(
            id,
            proposedFare: newFare,
          );
          renewalPromptedRideIds.remove(id);
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
        }
      }
    }

    await _cancelExpiredRideSilently(id);
  }

  Future<num?> _askSearchFare(num currentFare) async {
    final controller = TextEditingController(
      text: currentFare.toStringAsFixed(2),
    );
    final result = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Subir tu oferta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Nueva oferta',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Volver'),
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
            child: const Text('Buscar 3 min más'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
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

  Future<void> _createService() async {
    final originalPickup = pickup;
    final to = destination;
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
          return resolved ??
              'Origen · ${from.latitude.toStringAsFixed(5)}, ${from.longitude.toStringAsFixed(5)}';
        }(),
        () async {
          if (!_isExpressPlaceholderAddress(to.label)) {
            return to.label.trim();
          }
          final resolved = await _expressReverseGeocodeAddress(
            LatLng(to.latitude, to.longitude),
          );
          return resolved ??
              'Destino · ${to.latitude.toStringAsFixed(5)}, ${to.longitude.toStringAsFixed(5)}';
        }(),
      ]);
      if (!mounted) return;
      final resolvedPickupAddress = resolvedAddresses[0];
      final resolvedDestinationAddress = resolvedAddresses[1];

      final createdRide = await runExpressStateTransition<Map<String, dynamic>>(
        context,
        processingTitle: 'Buscando conductores…',
        processingSubtitle: 'Estamos publicando tu solicitud.',
        successTitle: 'Buscando conductores',
        successSubtitle: 'Tu solicitud ya está visible para conductores cercanos.',
        eventName: 'RIDE_REQUEST_CREATED',
        action: () => widget.service.createRideRequest(
          category: category,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo solicitar el viaje: ' + e.toString())),
      );
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> _selectOffer(Map<String, dynamic> offer) async {
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aceptar la oferta: ' + e.toString())),
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
          .cancelRideRequest(rideId, reason: reason)
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
          .cancelTrip(tripId, reason: reason)
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

  void _openTripTracking(Map<String, dynamic> trip) {
    final driverId = trip['driver_id']?.toString();
    if (driverId == null) return;
    final rawRide = trip['ride_requests'];
    final ride = rawRide is Map
        ? Map<String, dynamic>.from(rawRide)
        : <String, dynamic>{};

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceTrackingPage(
          title: 'Seguimiento del viaje',
          status: trip['status']?.toString() ?? '',
          driverId: driverId,
          pickupLatitude: asDouble(ride['pickup_latitude']),
          pickupLongitude: asDouble(ride['pickup_longitude']),
          destinationLatitude: asDouble(ride['destination_latitude']),
          destinationLongitude: asDouble(ride['destination_longitude']),
        ),
      ),
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
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Viajes programados'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onHistory();
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

  @override
  void dispose() {
    if (renewalDecisionOpen && renewalDecisionRideId != null) {
      unawaited(
        widget.service.cancelRideRequest(
          renewalDecisionRideId!,
          reason: 'Sin respuesta al vencer la búsqueda',
        ),
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    passengerOfferRealtimeDebounce?.cancel();
    zoneServiceCatalogDebounce?.cancel();
    passengerOfferBootstrapTimer?.cancel();
    passengerCriticalStateTimer?.cancel();
    passengerLiveOfferTimer?.cancel();
    zoneServiceCatalogChannel?.unsubscribe();
    unawaited(passengerOfferRealtimeSubscription?.cancel());
    unawaited(passengerForegroundPushSubscription?.cancel());
    mapController.dispose();
    sheetController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPassengerLiveOfferState());
      unawaited(_refreshPassengerCriticalState());
      _refreshHome();
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
                    currencyCode:
                        activeZone?['currency_code']?.toString() ?? 'BOB',
                    serviceType: serviceType,
                    category: category,
                    payment: payment,
                    fare: fare,
                    minimumFare:
                        asDouble(fareQuote['minimum_allowed_fare']) ??
                            asDouble(fareQuote['recommended_fare']) ??
                            fare.toDouble(),
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
                      setState(() {
                        serviceType = value;
                        fare = value == 'ride' ? 5 : 8;
                        fareManuallyEdited = false;
                        routeConfirmed = false;
                        scheduledFor = null;
                        destination = null;
                        routeDistanceKm = null;
                        routeDurationMinutes = null;
                        roadRoute = const [];
                      });
                      _refreshHome();
                    },
                    onCategory: (value) {
                      setState(() {
                        category = value;
                        fareManuallyEdited = false;
                      });
                      _refreshHome();
                      _refreshFareQuote();
                    },
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
                      setState(() => routeConfirmed = false);
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
                    onTripTracking: _openTripTracking,
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
        final darkHome = _riderHomeDark(context);
        final confirmRouteFraction =
            _routeConfirmationSheetFraction(context);
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

        PreviewDiagnosticsHub.updatePassengerUi(
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
                'ride_id': offerRide?['id']?.toString(),
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
                child: const _MapPin(
                  icon: Icons.local_taxi_rounded,
                  dark: false,
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
                child: _MapPin(
                  icon: beforePickup
                      ? Icons.trip_origin_rounded
                      : Icons.location_on_rounded,
                  dark: true,
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
            lines.add(
              Polyline(
                points: passengerActiveRoadRoute.length >= 2
                    ? passengerActiveRoadRoute
                    : <LatLng>[driverPoint, target],
                strokeWidth: 5,
                color: expressBlue,
              ),
            );
            final stageKey = activeTrip['id'].toString() + ':' + status;
            if (passengerMapTripStageKey != stageKey) {
              passengerMapTripStageKey = stageKey;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([driverPoint, target]),
                    padding: const EdgeInsets.fromLTRB(46, 120, 46, 330),
                  ),
                );
              });
            }
          }
        } else {
          passengerMapTripStageKey = null;
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
                child: const _MapPin(
                  icon: Icons.location_on_rounded,
                  dark: true,
                ),
              ),
            );
          }

          if (searchingNow && data?.openRide != null) {
            final ride = data!.openRide!;
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
                  width: 30,
                  height: 38,
                  child: _VehicleMapMarker(
                    vehicleType:
                        driver['vehicle_type']?.toString() ?? 'motorcycle',
                    scale: _expressMapMarkerScale(passengerMapZoom),
                    orientation:
                        (asDouble(driver['heading_degrees']) ?? 0) *
                            math.pi /
                            180,
                  ),
                ),
              );
            }
          }

          if (pickup != null && destination != null && !searchingNow) {
            final fallback = <LatLng>[
              LatLng(pickup!.latitude, pickup!.longitude),
              LatLng(destination!.latitude, destination!.longitude),
            ];
            lines.add(
              Polyline(
                points: roadRoute.length >= 2 ? roadRoute : fallback,
                strokeWidth: 5,
                color: expressBlue,
              ),
            );
          }
        }

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: current ?? expressFallback,
                    initialZoom: current == null ? 13 : 14.6,
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
              if ((!initialLoading || snapshot.hasError) &&
                  effectivePassengerOffers.isEmpty &&
                  !hasActivePassengerService &&
                  !effectivePassengerFlowMinimized)
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
                              offerRide!['id'].toString() +
                              '-' +
                              effectivePassengerOffers
                                  .map(_passengerOfferPresentationKey)
                                  .join('|'),
                        ),
                        ride: offerRide!,
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
              if (hasPassengerOffers &&
                  !passengerFlowMinimized &&
                  passengerFlowActive)
                Positioned(
                  top: 10,
                  left: 14,
                  child: SafeArea(
                    bottom: false,
                    child: _CircleButton(
                      icon: Icons.arrow_back_rounded,
                      onPressed: _backFromPassengerFlow,
                    ),
                  ),
                ),
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
  final String category;
  final String payment;
  final num fare;
  final num minimumFare;
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
    required this.category,
    required this.payment,
    required this.fare,
    required this.minimumFare,
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

    if (submittingRide) {
      return _PanelShell(
        controller: controller,
        darkSurface: _riderHomeDark(context),
        bottomPadding: 12 + MediaQuery.viewPaddingOf(context).bottom,
        children: const [
          _NoticeCard(
            icon: Icons.radar_rounded,
            title: 'Ofreciendo tu tarifa',
            subtitle:
                'Publicando tu tarifa y esperando la primera respuesta.',
          ),
          SizedBox(height: 12),
          LinearProgressIndicator(minHeight: 4),
        ],
      );
    }

    final showRideChooser = data.activeTrip == null &&
        data.activeDelivery == null &&
        data.openRide == null &&
        destination != null &&
        routeConfirmed;

    if (showRideChooser) {
      return _RideServiceChooserPanel(
        services: services,
        settings: settings,
        zoneName: zoneName,
        currencyCode: currencyCode,
        category: category,
        payment: payment,
        fare: fare,
        minimumFare: minimumFare,
        scheduledFor: scheduledFor,
        routeDistanceKm: routeDistanceKm,
        routeDurationMinutes: routeDurationMinutes,
        routing: routing,
        quoting: quoting,
        creating: creating,
        onReviewRoute: onReviewRoute,
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
                  title: 'Chat del viaje',
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
            Text(
              '¿A dónde vas?',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
                color: _riderText(context),
                height: 1.02,
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
            PassengerAdSlot(
              settings: settings,
              placement: PassengerAdPlacement.home,
            ),
            const SizedBox(height: 8),
          ] else if (!routeConfirmed) ...[
            Text(
              'Confirma tu ruta',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _riderText(context),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Elige tu viaje',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: _riderText(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onReviewRoute,
                  child: const Text('Cambiar'),
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
    final floor = clp
        ? minimumFare.toDouble().ceilToDouble()
        : double.parse(minimumFare.toDouble().toStringAsFixed(2));
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
              helperText:
                  'Mínimo recomendado: ' + _rideMoney(floor, currencyCode),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
            validator: (raw) {
              final value = num.tryParse(
                (raw ?? '').trim().replaceAll(',', '.'),
              );
              if (value == null) return 'Ingresa un monto válido.';
              if (value.toDouble() + .001 < floor) {
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
    if (result != null) onFare(clp ? result.ceil() : result);
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
                            ? 'El administrador tiene habilitado un solo método de pago.'
                            : 'Elige uno de los métodos habilitados por administración.',
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
                          child: ListTile(
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
                          ),
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

class _DriverMapHomeState extends State<DriverMapHome> {
  final mapController = MapController();
  final locationService = const ExpressLocationService();
  StreamSubscription? positionSubscription;
  StreamSubscription<String>? driverForegroundPushSubscription;
  RealtimeChannel? driverRideRequestsChannel;
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
  final Set<String> viewedRideRequestIds = <String>{};
  bool viewedRideRequestIdsLoaded = false;
  String? driverRequestPopupId;
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
  bool driverRideActionBusy = false;
  String? lastAnimatedDriverTripId;
  String? lastAnimatedDriverTripStatus;
  String? driverMapTripStageKey;
  String? driverActiveRoadRouteKey;
  List<LatLng> driverActiveRoadRoute = const [];
  bool driverActiveRoadRouteLoading = false;
  LatLng? driverLastCameraPoint;
  DateTime? driverLastCameraAt;
  DateTime? driverLastLocationSyncAt;
  LatLng? driverLastSyncedPoint;
  double? driverLastSyncedHeading;
  bool driverLocationSyncInFlight = false;
  bool? driverTrackingHighFrequency;
  DateTime? driverPriorityLoadedAt;
  DateTime? driverPendingRatingLoadedAt;
  final Set<String> driverAddressHydrationInFlight = <String>{};

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
    if (movedKm < .015 && elapsed < const Duration(seconds: 3)) return;

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

    final needsPickup = _isExpressPlaceholderAddress(ride['pickup_address']);
    final needsDestination =
        _isExpressPlaceholderAddress(ride['destination_address']);
    if (!needsPickup && !needsDestination) return;

    driverAddressHydrationInFlight.add(rideId);
    try {
      String? pickup;
      String? destination;

      final pickupLat = asDouble(ride['pickup_latitude']);
      final pickupLng = asDouble(ride['pickup_longitude']);
      if (needsPickup && pickupLat != null && pickupLng != null) {
        pickup = await _expressReverseGeocodeAddress(
          LatLng(pickupLat, pickupLng),
        );
      }

      final destinationLat = asDouble(ride['destination_latitude']);
      final destinationLng = asDouble(ride['destination_longitude']);
      if (needsDestination &&
          destinationLat != null &&
          destinationLng != null) {
        destination = await _expressReverseGeocodeAddress(
          LatLng(destinationLat, destinationLng),
        );
      }

      if (pickup != null) ride['pickup_address'] = pickup;
      if (destination != null) ride['destination_address'] = destination;
      if (mounted && (pickup != null || destination != null)) {
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
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(
              Icons.check_circle_outline_rounded,
              color: expressBlue,
              size: 42,
            ),
            title: const Text('¿Finalizar este viaje?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCash
                      ? 'Antes de finalizar, cobra $fareLabel en efectivo.'
                      : isDriverQr
                          ? 'Antes de finalizar, confirma que recibiste $fareLabel directamente en tu QR.'
                          : 'Monto del viaje: $fareLabel · ${_paymentLabel(payment)}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Confirma únicamente cuando el pasajero haya llegado a destino.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: expressMuted),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Finalizar viaje'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _notifyDriverOfferPending(bool locked) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onOfferPendingChanged?.call(locked);
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

    if (changed) _notifyDriverOfferPending(false);
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
    _notifyDriverOfferPending(true);

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
    super.initState();
    driverFuture = _load();
    _locate();

    driverForegroundPushSubscription =
        expressForegroundPushEvents().listen((type) {
      if (!mounted) return;
      if (type == 'ride_request') {
        if (driverOfferPendingRideId == null) _refreshDriverHome();
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
          callback: (_) {
            if (!mounted || busy || driverRequestPopupId != null) return;
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
          callback: (_) {
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
    final nextFuture = _load().whenComplete(() {
      driverRefreshInFlight = false;
    });
    setState(() => driverFuture = nextFuture);
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

  Future<void> _locate() async {
    try {
      final position = await locationService.currentPosition();
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      current = point;
      driverPosition.value = point;
      mapController.move(point, 15);
    } catch (_) {}
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
        locationService.positionStream(highFrequency: highFrequency).listen(
      (position) async {
        final point = LatLng(position.latitude, position.longitude);
        current = point;

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

        final heading = position.heading.isFinite ? position.heading : 0.0;
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

        if (mounted) {
          driverPosition.value = point;
          if (cachedData?.activeTrip != null) {
            _followActiveDriverTrip(point);
            setState(() {});
          }
        }
      },
      onError: (_) {},
    );
  }

  Future<_DriverStateData> _load() async {
    final profile = await widget.service.myDriverProfile() ??
        await widget.service.ensureDriverProfile();

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
        _notifyDriverOfferPending(false);
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
      rides = await widget.service.availableRideRequests();
      deliveries = await widget.service.availableDeliveries();
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

    String? title;
    String? subtitle;
    IconData icon = Icons.local_taxi_rounded;
    switch (status) {
      case 'driver_assigned':
        title = '¡Viaje confirmado!';
        subtitle = 'Tu oferta fue aceptada. Dirígete al punto de recogida.';
        icon = Icons.task_alt_rounded;
        break;
      case 'emergency':
        title = 'Alerta de emergencia';
        subtitle = 'El viaje cambió a estado de emergencia.';
        icon = Icons.sos_rounded;
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
      counterpartLabel: 'pasajero',
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
        // Al conectar, renovamos/registramos el token FCM en segundo plano.
        // Así un token que Firebase haya marcado inválido no deja al conductor
        // sin alertas hasta el próximo reinicio de la app.
        final accessToken = supabase.auth.currentSession?.accessToken;
        if (accessToken != null && accessToken.isNotEmpty) {
          unawaited(enablePushNotifications(accessToken));
        }

        final position = await locationService.currentPosition();
        final point = LatLng(position.latitude, position.longitude);
        await Future.wait<void>([
          widget.service.updateDriverDetails(
            latitude: position.latitude,
            longitude: position.longitude,
            headingDegrees: position.heading.isFinite ? position.heading : 0,
          ),
          widget.service.setDriverOnline(true),
        ]);
        current = point;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _offerRide(Map<String, dynamic> ride) async {
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
              (ride['pickup_address']?.toString() ?? 'Origen') +
                  ' → ' +
                  (ride['destination_address']?.toString() ?? 'Destino'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: fareController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tu tarifa',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: etaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Llegas en (minutos)',
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
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    final amount = num.tryParse(
      fareController.text.trim().replaceAll(',', '.'),
    );
    final eta = int.tryParse(etaController.text.trim());
    fareController.dispose();
    etaController.dispose();

    if (confirmed != true || amount == null || eta == null) return;

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
        ),
      );
      if (!mounted) return;
      _startDriverOfferWait(offer, ride['id'].toString());
      _refreshDriverHome();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo ofertar: ' + e.toString())),
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
        ),
      );
      if (!mounted) return;
      _startDriverOfferWait(offer, ride['id'].toString());
      _refreshDriverHome();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo enviar la oferta: ' + e.toString()),
        ),
      );
    }
  }

  Future<void> _acceptRideAtPassengerFare(
    Map<String, dynamic> ride,
  ) async {
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
        ),
      );
      if (!mounted) return;
      _startDriverOfferWait(offer, ride['id'].toString());
      _refreshDriverHome();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aceptar la tarifa: ' + e.toString())),
      );
    }
  }

  Future<void> _claimDelivery(Map<String, dynamic> delivery) async {
    try {
      await widget.service.claimDelivery(delivery['id'].toString());
      if (!mounted) return;
      _refreshDriverHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aceptar: ' + e.toString())),
      );
    }
  }

  void _openTripTracking(Map<String, dynamic> trip) {
    final rawRide = trip['ride_requests'];
    final ride = rawRide is Map
        ? Map<String, dynamic>.from(rawRide)
        : <String, dynamic>{};
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceTrackingPage(
          title: 'Ruta del viaje',
          status: trip['status']?.toString() ?? '',
          driverId: widget.service.userId,
          pickupLatitude: asDouble(ride['pickup_latitude']),
          pickupLongitude: asDouble(ride['pickup_longitude']),
          destinationLatitude: asDouble(ride['destination_latitude']),
          destinationLongitude: asDouble(ride['destination_longitude']),
        ),
      ),
    );
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

  String _tripActionLabel(String status) {
    switch (status) {
      case 'driver_arriving':
        return 'Llegué';
      case 'driver_waiting':
        return 'Llegué';
      case 'in_progress':
        return 'Iniciar viaje';
      case 'completed':
        return 'Completar viaje';
      default:
        return 'Continuar';
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

  String _deliveryActionLabel(String status) {
    switch (status) {
      case 'picked_up':
        return 'Paquete recogido';
      case 'in_transit':
        return 'Salir a entregar';
      case 'delivered':
        return 'Marcar entregado';
      default:
        return 'Continuar';
    }
  }

  Future<void> _advanceTrip(Map<String, dynamic> trip) async {
    if (driverRideActionBusy) return;
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
      pin = await _askBoardingPin();
      if (pin == null || !mounted) return;
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

    final previousData = cachedData;
    final canOptimisticallyAdvance =
        next == 'driver_arriving' ||
        next == 'driver_waiting' ||
        next == 'in_progress';

    setState(() {
      driverRideActionBusy = true;
      if (canOptimisticallyAdvance && previousData?.activeTrip != null) {
        final optimisticTrip =
            Map<String, dynamic>.from(previousData!.activeTrip!);
        optimisticTrip['status'] = next;
        final optimistic = _DriverStateData(
          service: previousData.service,
          profile: previousData.profile,
          rides: previousData.rides,
          deliveries: previousData.deliveries,
          activeTrip: optimisticTrip,
          activeDelivery: previousData.activeDelivery,
          counterpart: previousData.counterpart,
          pendingRating: previousData.pendingRating,
        );
        cachedData = optimistic;
        driverFuture = Future.value(optimistic);
        lastAnimatedDriverTripId = trip['id']?.toString();
        lastAnimatedDriverTripStatus = next;
      }
    });

    try {
      await runExpressStateTransition<void>(
        context,
        processingTitle: processingTitle,
        processingSubtitle: 'No cierres esta pantalla mientras confirmamos.',
        successTitle: successTitle,
        successSubtitle: successSubtitle,
        eventName: 'DRIVER_TRIP_' + next.toUpperCase(),
        action: () async {
          if (next == 'in_progress') {
            await widget.service.startTripWithPin(
              tripId: trip['id'].toString(),
              pin: pin!,
            );
          } else {
            await widget.service.advanceTrip(trip['id'].toString(), next);
          }
        },
        onSuccess: (_) {
          if (canOptimisticallyAdvance) return;
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
      if (canOptimisticallyAdvance && previousData != null) {
        cachedData = previousData;
        driverFuture = Future.value(previousData);
        lastAnimatedDriverTripId = trip['id']?.toString();
        lastAnimatedDriverTripStatus = trip['status']?.toString();
        setState(() {});
      }
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
    try {
      await widget.service.cancelTrip(trip['id'].toString(), reason: reason);
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

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
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
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Seguridad y SOS'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onSafety();
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

    if (candidates.isEmpty) return;

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
    String popupId,
  ) async {
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

    final fallback = <LatLng>[
      if (current != null) current!,
      LatLng(pickupLat, pickupLng),
      LatLng(destinationLat, destinationLng),
    ];
    if (mounted && driverRequestPopupId == popupId) {
      setState(() => driverPopupRoadRoute = fallback);
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
        points.addAll(
          toPickup.points.length >= 2
              ? toPickup.points
              : <LatLng>[current!, pickupPoint],
        );
      } else {
        points.add(pickupPoint);
      }

      final toDestination = await ExpressMapProvider.drivingRoute(
        from: pickupPoint,
        to: destinationPoint,
      );
      final destinationRoute = toDestination.points.length >= 2
          ? toDestination.points
          : <LatLng>[pickupPoint, destinationPoint];
      if (points.isNotEmpty &&
          destinationRoute.isNotEmpty &&
          points.last == destinationRoute.first) {
        points.addAll(destinationRoute.skip(1));
      } else {
        points.addAll(destinationRoute);
      }

      if (!mounted ||
          driverRequestPopupId != popupId ||
          points.length < 2) {
        return;
      }
      setState(() => driverPopupRoadRoute = points);
    } catch (_) {
      // Mantener la línea directa si Mapbox y el respaldo no responden.
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
    final popupExpiresAt = automatic
        ? DateTime.now().toUtc().add(const Duration(seconds: 30))
        : null;
    setState(() {
      driverRequestPopupId = id;
      driverRequestPopupAutomatic = automatic;
      driverRequestPopupExpiresAt = popupExpiresAt;
      driverRequestPopupRemaining = automatic ? 30 : 0;
      driverPopupRoadRoute = const [];
    });
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
        driverOfferPendingRideId != null) {
      return;
    }

    driverRequestQueueAdvancing = true;
    try {
      final freshRides = await widget.service.availableRideRequests();
      if (!mounted || driverRequestPopupId != null) return;

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
      }
    } catch (_) {
      // El refresco periódico volverá a consultar si la red falla.
    } finally {
      driverRequestQueueAdvancing = false;
    }
  }

  void _openRequestFromList(Map<String, dynamic> ride) {
    _openDriverRequestPopup(ride, automatic: false);
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
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final dark = _riderHomeDark(sheetContext);
        final surface = _riderSurface(sheetContext);
        final softSurface = _riderSoftSurface(sheetContext);
        final border = _riderBorder(sheetContext);
        final textColor = _riderText(sheetContext);
        final muted = _riderMuted(sheetContext);
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
                          rides.length.toString(),
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
                  child: rides.isEmpty
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
                          itemCount: rides.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final ride = rides[index];
                            final pickup =
                                ride['pickup_address']?.toString() ??
                                    'Origen';
                            final destination =
                                ride['destination_address']?.toString() ??
                                    'Destino';
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
                            final category =
                                ride['category']?.toString() ?? 'Viaje';
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
                                      _openRequestFromList(ride);
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
                                          Icons.local_taxi_rounded,
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
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    driverRequestPopupTimer?.cancel();
    driverOfferPendingTimer?.cancel();
    positionSubscription?.cancel();
    driverForegroundPushSubscription?.cancel();
    driverRideRequestsChannel?.unsubscribe();
    driverNotificationsChannel?.unsubscribe();
    driverZoneServicesChannel?.unsubscribe();
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

        Map<String, dynamic>? driverPopupRide;
        if (driverRequestPopupId != null && data != null) {
          for (final ride in data.rides) {
            if (ride['id']?.toString() == driverRequestPopupId) {
              driverPopupRide = ride;
              break;
            }
          }
        }

        LatLng? popupPickup;
        LatLng? popupDestination;
        if (driverPopupRide != null) {
          final pickupLat = asDouble(driverPopupRide['pickup_latitude']);
          final pickupLng = asDouble(driverPopupRide['pickup_longitude']);
          final destinationLat =
              asDouble(driverPopupRide['destination_latitude']);
          final destinationLng =
              asDouble(driverPopupRide['destination_longitude']);
          if (pickupLat != null && pickupLng != null) {
            popupPickup = LatLng(pickupLat, pickupLng);
          }
          if (destinationLat != null && destinationLng != null) {
            popupDestination = LatLng(destinationLat, destinationLng);
          }
        }

        if (driverPopupRide != null) {
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
                activeTripTarget!,
              );
              final stageKey =
                  trip['id'].toString() + ':' + activeTripStatus.toString();
              if (driverMapTripStageKey != stageKey) {
                driverMapTripStageKey = stageKey;
                final origin = current!;
                final target = activeTripTarget!;
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
                    if (driverPopupRide != null)
                      PolylineLayer(
                        polylines: [
                          if (driverPopupRoadRoute.length > 1)
                            Polyline(
                              points: driverPopupRoadRoute,
                              strokeWidth: 5,
                              color: expressBlue,
                            )
                          else ...[
                            if (current != null && popupPickup != null)
                              Polyline(
                                points: [current!, popupPickup!],
                                strokeWidth: 5,
                                color: expressBlue,
                              ),
                            if (popupPickup != null &&
                                popupDestination != null)
                              Polyline(
                                points: [popupPickup!, popupDestination!],
                                strokeWidth: 5,
                                color: const Color(0xFF12B76A),
                              ),
                          ],
                        ],
                      ),
                    if (driverPopupRide == null &&
                        activeTripTarget != null)
                      ValueListenableBuilder<LatLng?>(
                        valueListenable: driverPosition,
                        builder: (context, point, _) {
                          if (point == null) return const SizedBox.shrink();
                          return PolylineLayer(
                            polylines: [
                              Polyline(
                                points: driverActiveRoadRoute.length >= 2
                                    ? driverActiveRoadRoute
                                    : <LatLng>[point, activeTripTarget!],
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
                                child: const _MapPin(
                                  icon: Icons.local_taxi_rounded,
                                  dark: false,
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
                  child: Row(
                    children: [
                      _CircleButton(
                        icon: Icons.menu_rounded,
                        onPressed: _showDriverMenu,
                        enabled: !hasActiveDriverService,
                      ),
                      const Spacer(),
                      _ModeBadge(
                        icon: Icons.drive_eta_rounded,
                        text: 'Conductor',
                        onPressed: widget.onSwitchMode,
                        enabled: !hasActiveDriverService,
                      ),
                      const SizedBox(width: 8),
                      if (data != null)
                        _OnlineBadge(
                          approved:
                              data.profile['approval_status'] == 'approved',
                          online: hasActiveDriverService
                              ? false
                              : data.profile['online_status'] == 'online',
                          busy: busy,
                          locked: hasActiveDriverService,
                          onPressed: () => _toggleOnline(data.profile),
                        ),
                    ],
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
              if (driverPopupRide == null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSize(
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
                            onRequests: () => _showDriverRequests(data.rides),
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
                ),
              if (driverOfferPendingRideId != null &&
                  data?.activeTrip == null)
                Positioned.fill(
                  child: _DriverOfferWaitingOverlay(
                    remainingSeconds: driverOfferPendingRemaining,
                  ),
                ),
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

    return AbsorbPointer(
      absorbing: true,
      child: Material(
        color: const Color(0x73000000),
        child: SafeArea(
          child: Center(
            child: Container(
              width: 310,
              margin: const EdgeInsets.symmetric(horizontal: 24),
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
      fallback: 'Origen',
    );
    final destination = _expressDriverRouteLabel(
      ride,
      addressKey: 'destination_address',
      latitudeKey: 'destination_latitude',
      longitudeKey: 'destination_longitude',
      fallback: 'Destino',
    );
    final fare = asDouble(ride['proposed_fare']) ?? 0;
    final tripKm = asDouble(ride['route_distance_km']);
    final category = ride['category']?.toString() ?? 'Viaje';
    final payment = ride['payment_method']?.toString();
    final pickupDistance = _pickupDistanceKm(
      current,
      asDouble(ride['pickup_latitude']),
      asDouble(ride['pickup_longitude']),
    );
    final dark = _riderHomeDark(context);
    final panel = dark ? const Color(0xFF161616) : Colors.white;
    final soft = dark ? const Color(0xFF232323) : const Color(0xFFF5F7FA);
    final quick1 = (fare + 1).clamp(1, 9999).toDouble();
    final quick2 = (fare + 2).clamp(1, 9999).toDouble();
    final quick3 = (fare + 3).clamp(1, 9999).toDouble();

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
            Positioned(
              top: 2,
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
                      child: const Text(
                        'Solicitud de viaje',
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
                          'Tarifa del pasajero',
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
                                onPressed: () => onQuickOffer(amount),
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
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton.icon(
                              onPressed: onOffer,
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: const Text('Otro monto'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: TextButton(
                              onPressed: onClose,
                              style: TextButton.styleFrom(
                                foregroundColor: _riderMuted(context),
                              ),
                              child: const Text('Cerrar'),
                            ),
                          ),
                        ),
                      ],
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

    return _PanelShell(
      controller: controller,
      darkSurface: _riderHomeDark(context),
      bottomPadding: 6,
      children: [
        if (data.pendingRating != null) ...[
          _PendingRatingCard(
            pending: data.pendingRating!,
            onTap: () => onRatePending(data.pendingRating!),
            counterpartLabel: 'pasajero',
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
                  title: 'Chat del viaje',
                  tripId: data.activeTrip!['id'].toString(),
                ),
              ),
            ),
            onCall: () => ExpressPrivateVoiceCall.instance.startTripCall(
              context: context,
              service: data.service,
              trip: data.activeTrip!,
            ),
            primaryLabel: _driverTripNextLabel(
              data.activeTrip!['status']?.toString(),
            ),
            onPrimary: _driverTripNextLabel(
                      data.activeTrip!['status']?.toString(),
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
            subtitle:
                _deliveryStatus(data.activeDelivery!['status']?.toString()),
            detail: 'Cliente del delivery',
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
            primaryLabel: _driverDeliveryNextLabel(
              data.activeDelivery!['status']?.toString(),
            ),
            onPrimary: _driverDeliveryNextLabel(
                      data.activeDelivery!['status']?.toString(),
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
                'Completa licencia y vehículo. El administrador debe aprobar tu perfil.',
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
          if (data.deliveries.isNotEmpty) ...[
            _DriverDeliveryOpportunityCard(
              delivery: data.deliveries.first,
              onAccept: () => onDelivery(data.deliveries.first),
            ),
            const SizedBox(height: 10),
          ],
          _DriverRequestsButton(
            count: data.rides.length,
            onTap: onRequests,
          ),
          const SizedBox(height: 10),
          if (data.rides.isEmpty && data.deliveries.isEmpty)
            const _NoticeCard(
              icon: Icons.radar_rounded,
              title: 'Esperando solicitudes…',
              subtitle:
                  'Cuando llegue un viaje o delivery aparecerá aquí automáticamente.',
            )
          else if (data.rides.isNotEmpty)
            const _NoticeCard(
              icon: Icons.notifications_active_outlined,
              title: 'Buscando viajes cerca',
              subtitle:
                  'La solicitud prioritaria aparece arriba. Toca “Solicitudes” para ver todas.',
            )
          else
            const _NoticeCard(
              icon: Icons.local_shipping_outlined,
              title: 'Delivery disponible',
              subtitle:
                  'Revisa la ganancia y acepta cuando estés listo.',
            ),
        ],
      ],
    );
  }
}

class _DriverDeliveryOpportunityCard extends StatelessWidget {
  final Map<String, dynamic> delivery;
  final VoidCallback onAccept;

  const _DriverDeliveryOpportunityCard({
    required this.delivery,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final surface = dark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = _riderBorder(context);
    final text = _riderText(context);
    final muted = _riderMuted(context);
    final currency = delivery['currency']?.toString().toUpperCase() ?? 'CLP';
    final earning = asDouble(delivery['proposed_fare']) ?? 0;
    final customerCharge = asDouble(delivery['customer_charge_amount']);
    final priority = delivery['marketplace_priority'] == true;
    final marketplace = delivery['marketplace_order_id'] != null;
    final payment = delivery['payment_method']?.toString() ?? 'cash';
    final prepaid = payment != 'cash';
    final pickup = delivery['pickup_address']?.toString().trim();
    final dropoff = delivery['dropoff_address']?.toString().trim();

    String money(num value) {
      final rounded = value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(2);
      return currency == 'BOB'
          ? 'Bs ' + rounded
          : currency == 'CLP'
              ? 'CLP ' + rounded
              : currency + ' ' + rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: priority ? const Color(0xFFF5B700) : border,
          width: priority ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: priority
                      ? const Color(0xFFFFF6D8)
                      : const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  priority
                      ? Icons.bolt_rounded
                      : Icons.local_shipping_rounded,
                  color: priority
                      ? const Color(0xFFB77900)
                      : expressBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      priority
                          ? 'Envío Plus · prioridad'
                          : marketplace
                              ? 'Pedido Express Delivery'
                              : 'Delivery disponible',
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tu ganancia: ' + money(earning),
                      style: const TextStyle(
                        color: Color(0xFF14804A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pickup != null && pickup.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Retiro: ' + pickup,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
          if (dropoff != null && dropoff.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Entrega: ' + dropoff,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: prepaid
                  ? const Color(0xFFE8F8EF)
                  : dark
                      ? const Color(0xFF292929)
                      : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              prepaid
                  ? 'Pedido pagado · no cobrar al cliente'
                  : customerCharge == null
                      ? 'Pago en efectivo'
                      : 'Cobrar al cliente: ' + money(customerCharge),
              style: TextStyle(
                color: prepaid ? const Color(0xFF14804A) : text,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAccept,
              icon: const Icon(Icons.check_rounded),
              label: Text(
                priority ? 'Aceptar Envío Plus' : 'Aceptar delivery',
              ),
            ),
          ),
        ],
      ),
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

  const _RouteSummary({
    required this.distanceKm,
    required this.durationMinutes,
    required this.fare,
    required this.currencyCode,
    required this.routing,
    required this.quoting,
    this.showFare = true,
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
                    text: 'Sugerido ' + _rideMoney(fare, currencyCode),
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
                    kind == 'delivery'
                        ? 'Califica al $counterpartLabel'
                        : 'Califica al $counterpartLabel',
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

class _ToggleTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _ToggleTile({
    required this.selected,
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? expressBlue : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : expressDark),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: selected ? Colors.white : expressDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
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

class _RecentTripsPreview extends StatelessWidget {
  final ExpressService service;
  final VoidCallback onHistory;

  const _RecentTripsPreview({
    required this.service,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: service.myRideRequests(),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (snapshot.connectionState == ConnectionState.waiting &&
            rows.isEmpty) {
          return const SizedBox(
            height: 36,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (rows.isEmpty) {
          return Text(
            'Todavía no tienes viajes recientes.',
            style: TextStyle(
              color: _riderMuted(context),
              fontSize: 11,
            ),
          );
        }

        final recent = rows.take(4).toList(growable: false);
        return Column(
          children: [
            for (var i = 0; i < recent.length; i++) ...[
              _RecentTripPreviewTile(
                row: recent[i],
                onTap: onHistory,
              ),
              if (i < recent.length - 1) const SizedBox(height: 6),
            ],
          ],
        );
      },
    );
  }
}

class _RecentTripPreviewTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  const _RecentTripPreviewTile({
    required this.row,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pickup = row['pickup_address']?.toString().trim();
    final destination = row['destination_address']?.toString().trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: _riderSoftSurface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _riderBorder(context)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.history_rounded,
              color: expressBlue,
              size: 17,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                (pickup == null || pickup.isEmpty ? 'Origen' : pickup) +
                    ' → ' +
                    (destination == null || destination.isEmpty
                        ? 'Destino'
                        : destination),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _riderText(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: _riderMuted(context),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _PassengerFixedServiceBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _PassengerFixedServiceBar({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _riderSurface(context),
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: _riderBorder(context)),
            ),
          ),
          child: _PassengerServiceBar(
            selected: selected,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _PassengerServiceBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _PassengerServiceBar({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: _PassengerServiceButton(
              selected: selected == 'ride',
              icon: Icons.local_taxi_rounded,
              label: 'Viaje Express',
              onTap: () => onChanged('ride'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PassengerServiceButton(
              selected: selected == 'delivery',
              icon: Icons.local_shipping_rounded,
              label: 'Delivery',
              onTap: () => onChanged('delivery'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengerServiceButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PassengerServiceButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFEAF2FF)
                    : _riderHomeDark(context)
                    ? const Color(0xFF262626)
                    : const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                icon,
                color: selected ? expressBlue : _riderMuted(context),
                size: 21,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? expressBlue : _riderMuted(context),
                fontSize: 10,
                fontWeight:
                    selected ? FontWeight.w900 : FontWeight.w700,
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
  final bool prominent;

  const _AddressTile({
    required this.icon,
    required this.text,
    required this.onTap,
    this.prominent = false,
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

class _RideServiceChooserPanel extends StatelessWidget {
  final List<Map<String, dynamic>> services;
  final Map<String, dynamic> settings;
  final String? zoneName;
  final String currencyCode;
  final String category;
  final String payment;
  final num fare;
  final num minimumFare;
  final DateTime? scheduledFor;
  final double? routeDistanceKm;
  final int? routeDurationMinutes;
  final bool routing;
  final bool quoting;
  final bool creating;
  final VoidCallback onReviewRoute;
  final ValueChanged<String> onCategory;
  final ValueChanged<num> onFare;
  final VoidCallback onEditFare;
  final VoidCallback onSchedule;
  final VoidCallback onPayment;
  final VoidCallback onCreate;

  const _RideServiceChooserPanel({
    required this.services,
    required this.settings,
    required this.zoneName,
    required this.currencyCode,
    required this.category,
    required this.payment,
    required this.fare,
    required this.minimumFare,
    required this.scheduledFor,
    required this.routeDistanceKm,
    required this.routeDurationMinutes,
    required this.routing,
    required this.quoting,
    required this.creating,
    required this.onReviewRoute,
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

  String get selectedLabel =>
      selectedService['name']?.toString() ?? 'Express';

  bool get selectedAvailable => selectedService['enabled'] != false;

  IconData get selectedIcon => _rideServiceIcon(selectedService);

  int get selectedSeats => _rideServiceSeats(selectedService);

  String _durationText() {
    final minutes = routeDurationMinutes;
    return minutes == null ? 'Calculando tiempo' : minutes.toString() + ' min';
  }

  void _changeFare(double delta) {
    if (quoting) return;
    final clp = currencyCode.toUpperCase() == 'CLP';
    final next = (fare.toDouble() + delta)
        .clamp(minimumFare.toDouble(), 9999999.0);
    onFare(clp ? next.ceil() : double.parse(next.toStringAsFixed(2)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final surface = dark ? const Color(0xFF121212) : Colors.white;
    final footer = dark ? const Color(0xFF151515) : const Color(0xFFFDFDFD);

    if (services.isEmpty) {
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
              padding: const EdgeInsets.fromLTRB(18, 10, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Elige tu viaje',
                          style: TextStyle(
                            color: _riderText(context),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (zoneName != null)
                          Text(
                            zoneName! + ' · ' + currencyCode.toUpperCase(),
                            style: TextStyle(
                              color: _riderMuted(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onReviewRoute,
                    child: const Text('Cambiar'),
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
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: _RideFareControlCard(
                icon: selectedIcon,
                title: selectedLabel,
                seats: selectedSeats,
                durationText: _durationText(),
                fare: fare,
                minimumFare: minimumFare,
                currencyCode: currencyCode,
                quoting: quoting,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Servicios',
                    style: TextStyle(
                      color: _riderMuted(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  _RideServiceSlots(
                    services: services,
                    selectedKey: category,
                    onSelected: onCategory,
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
                      onPressed: creating || quoting || !selectedAvailable
                          ? null
                          : onCreate,
                      icon: creating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.local_taxi_rounded),
                      label: Text(
                        selectedAvailable
                            ? 'Confirmar ' + selectedLabel
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
  final IconData icon;
  final String title;
  final int seats;
  final String durationText;
  final num fare;
  final num minimumFare;
  final String currencyCode;
  final bool quoting;
  final VoidCallback onEdit;
  final VoidCallback? onDecrease;
  final VoidCallback onIncrease;

  const _RideFareControlCard({
    required this.icon,
    required this.title,
    required this.seats,
    required this.durationText,
    required this.fare,
    required this.minimumFare,
    required this.currencyCode,
    required this.quoting,
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
                            Icons.person_rounded,
                            size: 14,
                            color: _riderMuted(context),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            seats.toString() + ' · ' + durationText,
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
                  onPressed: quoting ? null : onEdit,
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
                  onTap: quoting ? null : onDecrease,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        quoting
                            ? 'Calculando…'
                            : _zoneMoneyPrefix(currencyCode) +
                                ' ' +
                                fare.toString(),
                        style: TextStyle(
                          color: _riderText(context),
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Mínimo recomendado · ' +
                            _rideMoney(minimumFare, currencyCode),
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
                  onTap: quoting ? null : onIncrease,
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

class _CategoryTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 7),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? (_riderHomeDark(context)
                  ? const Color(0xFF17315A)
                  : const Color(0xFFEAF2FF))
              : _riderSoftSurface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? expressBlue : _riderBorder(context),
            width: selected ? 1.7 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: expressBlue, size: 24),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: selected ? expressBlue : _riderText(context),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: _riderMuted(context),
              ),
            ),
          ],
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
                (ride['pickup_address']?.toString() ?? 'Origen') +
                    ' → ' +
                    (ride['destination_address']?.toString() ?? 'Destino'),
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

class _SearchRoundDecisionDialog extends StatefulWidget {
  final double currentFare;
  final String currency;

  const _SearchRoundDecisionDialog({
    required this.currentFare,
    required this.currency,
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
    return AlertDialog(
      title: const Text('¿Quieres seguir buscando?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pasaron 3 minutos sin asignar conductor. Puedes seguir buscando, subir tu oferta o cancelar.',
          ),
          const SizedBox(height: 10),
          Text(
            'Oferta actual: ' +
                _rideMoney(widget.currentFare, widget.currency),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Si no respondes, la solicitud se cancelará en $remaining s.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('Cancelar'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, 'raise'),
          child: const Text('Subir oferta'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'continue'),
          child: const Text('Seguir 3 min'),
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
      if (seenOfferKeys.contains(key)) continue;

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
    final createdAt =
        DateTime.tryParse(widget.ride['created_at']?.toString() ?? '')?.toUtc();
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
              if (progress != null) ...[
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
              CircleAvatar(
                radius: 21,
                backgroundColor: expressBlue.withValues(alpha: .12),
                backgroundImage: avatar != null && avatar.isNotEmpty
                    ? NetworkImage(avatar)
                    : null,
                child: avatar == null || avatar.isEmpty
                    ? const Icon(Icons.person_rounded, color: expressBlue)
                    : null,
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
              _DriverViewerAvatar(
                viewer: {
                  'full_name': name ?? 'Conductor',
                  'avatar_url': driverUser['avatar_url'],
                },
                size: 38,
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
                child: const Icon(
                  Icons.local_taxi_rounded,
                  color: expressBlue,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tripStatus(status),
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      passengerName == null || passengerName.isEmpty
                          ? 'Pasajero del viaje'
                          : passengerName,
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
            _DriverPickupWaitNotice(
              waitingSince:
                  trip['driver_waiting_since']?.toString(),
              passengerOnWayAt:
                  trip['passenger_on_way_at']?.toString(),
            ),
            const SizedBox(height: 8),
            Text(
              'Pide al pasajero el PIN de 4 dígitos antes de iniciar el viaje.',
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
  late DateTime fallbackStart;

  @override
  void initState() {
    super.initState();
    fallbackStart = DateTime.now().toUtc();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  int get remainingSeconds {
    final parsed =
        DateTime.tryParse(widget.waitingSince ?? '')?.toUtc();
    final start = parsed ?? fallbackStart;
    final elapsed = DateTime.now().toUtc().difference(start).inSeconds;
    return (300 - elapsed).clamp(0, 300).toInt();
  }

  String get clock {
    final seconds = remainingSeconds;
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
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
                  ? 'El pasajero avisó “Ya voy”. Tiempo de abordaje: $clock'
                  : expired
                      ? 'Se cumplió el tiempo de cortesía de 5 minutos.'
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
                child: const Icon(
                  Icons.local_taxi_rounded,
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
                CircleAvatar(
                  radius: 25,
                  backgroundColor:
                dark ? const Color(0xFF17315E) : const Color(0xFFEAF2FF),
                  backgroundImage:
                      avatar != null && avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                  child: avatar == null || avatar.isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          color: expressBlue,
                        )
                      : null,
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
          if (beforeBoarding && pin != null && pin.isNotEmpty) ...[
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
          if (status == 'driver_waiting') ...[
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
          PassengerAdSlot(
            settings: adSettings,
            placement: PassengerAdPlacement.activeTrip,
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

  @override
  void initState() {
    super.initState();
    acknowledged = widget.alreadyAcknowledged;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant _PassengerPickupWaitNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alreadyAcknowledged) acknowledged = true;
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String _remainingText() {
    final since = widget.waitingSince?.toLocal();
    if (since == null) return '5:00';
    final deadline = since.add(const Duration(minutes: 5));
    final remaining = deadline.difference(now);
    if (remaining <= Duration.zero) return '00:00';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
                  time == '00:00'
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
                        ? 'Offline'
                        : busy
                            ? (online ? 'Desconectando…' : 'Activando…')
                            : active
                                ? 'En línea'
                                : 'Offline',
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
    final multiplier = asDouble(quote['demand_multiplier']) ?? 1;
    final level = quote['demand_level']?.toString() ?? 'normal';
    final changePercent =
        (((multiplier - 1) * 100).round()).clamp(-99, 999).toInt();

    final Color background;
    final Color foreground;
    final IconData icon;
    final String title;
    switch (level) {
      case 'low':
        background = const Color(0xFFEAF7EF);
        foreground = const Color(0xFF067647);
        icon = Icons.trending_down_rounded;
        title = 'Demanda baja';
        break;
      case 'critical':
        background = const Color(0xFFFFE9E7);
        foreground = const Color(0xFFB42318);
        icon = Icons.local_fire_department_rounded;
        title = 'Demanda muy alta';
        break;
      case 'high':
      case 'very_high':
        background = const Color(0xFFFFF0E5);
        foreground = const Color(0xFFB54708);
        icon = Icons.trending_up_rounded;
        title = 'Alta demanda';
        break;
      case 'medium':
      case 'elevated':
        background = const Color(0xFFFFF7D6);
        foreground = const Color(0xFF8A6100);
        icon = Icons.bolt_rounded;
        title = 'Demanda mayor';
        break;
      default:
        background = const Color(0xFFEAF7EF);
        foreground = const Color(0xFF067647);
        icon = Icons.check_circle_rounded;
        title = 'Demanda normal';
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
              title +
                  ' · ' +
                  (changePercent > 0 ? '+' : '') +
                  changePercent.toString() +
                  '%',
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

String? _driverTripNextLabel(String? status) {
  switch (status) {
    case 'driver_assigned':
      return 'Llegué';
    case 'driver_arriving':
      return 'Llegué';
    case 'driver_waiting':
      return 'Iniciar viaje';
    case 'in_progress':
      return 'Completar viaje';
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
  return ExpressBaseTileLayer(
    key: ValueKey<String>(
      dark ? 'express-map-dark' : 'express-map-light',
    ),
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

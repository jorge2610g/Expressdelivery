import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

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
import 'location_picker.dart';
import 'location_service.dart';
import 'push_notifications.dart';
import 'preview_diagnostics_hub.dart';
import 'service_tracking.dart';
import 'services/express_service.dart';

const Color expressBlue = Color(0xFF0B57D0);
const Color expressDark = Color(0xFF101828);
const Color expressMuted = Color(0xFF667085);
const LatLng expressFallback = LatLng(-14.8333, -64.9000);

Future<List<LatLng>> _expressRoadRoute(LatLng from, LatLng to) async {
  final fallback = <LatLng>[from, to];
  try {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/' +
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}' +
          '?overview=full&geometries=geojson',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) return fallback;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['routes'] is! List) return fallback;
    final routes = decoded['routes'] as List;
    if (routes.isEmpty || routes.first is! Map) return fallback;
    final geometry = (routes.first as Map)['geometry'];
    if (geometry is! Map || geometry['coordinates'] is! List) return fallback;
    final points = <LatLng>[];
    for (final raw in geometry['coordinates'] as List) {
      if (raw is List && raw.length >= 2) {
        final lng = (raw[0] as num?)?.toDouble();
        final lat = (raw[1] as num?)?.toDouble();
        if (lat != null && lng != null) points.add(LatLng(lat, lng));
      }
    }
    return points.length >= 2 ? points : fallback;
  } catch (_) {
    return fallback;
  }
}

double? asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
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
  Map<String, dynamic> pending,
) async {
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
              ? '¿Cómo estuvo tu delivery?'
              : '¿Cómo estuvo tu viaje?',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tu calificación ayuda a mantener una comunidad segura y confiable.',
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

class PassengerMapHome extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic>? initialState;
  final VoidCallback onChanged;
  final VoidCallback onHardReset;
  final VoidCallback onSwitchMode;
  final VoidCallback onHistory;
  final VoidCallback onPayments;
  final VoidCallback onProfile;
  final VoidCallback onSavedPlaces;
  final VoidCallback onSafety;

  const PassengerMapHome({
    super.key,
    required this.service,
    this.initialState,
    required this.onChanged,
    required this.onHardReset,
    required this.onSwitchMode,
    required this.onHistory,
    required this.onPayments,
    required this.onProfile,
    required this.onSavedPlaces,
    required this.onSafety,
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
  String category = 'economy';
  String payment = 'cash';
  num fare = 5;
  DateTime? scheduledFor;
  bool locating = false;
  bool creating = false;
  bool routing = false;
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
  _PassengerStateData? cachedData;
  late Future<_PassengerStateData> homeFuture;
  int loadRevision = 0;
  int panelRevision = 0;
  int passengerOfferStateRevision = 0;
  Timer? timer;
  bool passengerOfferActionBusy = false;
  bool homeRefreshInFlight = false;
  bool homeRefreshQueued = false;
  StreamSubscription<List<Map<String, dynamic>>>?
      passengerOfferRealtimeSubscription;
  StreamSubscription<String>? passengerForegroundPushSubscription;
  String? passengerOfferRealtimeRideId;
  Timer? passengerOfferRealtimeDebounce;
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
      });
    } else {
      driverOfferPendingRideId = null;
      driverOfferPendingRemaining = 0;
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
    );

    driverOfferPendingTimer?.cancel();
    setState(() {
      driverOfferPendingRideId = rideRequestId;
      driverOfferPendingRemaining = remaining;
    });
    _notifyDriverOfferPending(true);

    driverOfferPendingTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || driverOfferPendingRideId != rideRequestId) {
        timer.cancel();
        return;
      }
      if (driverOfferPendingRemaining <= 1) {
        timer.cancel();
        _clearDriverOfferWait(refresh: true);
        return;
      }
      setState(() => driverOfferPendingRemaining--);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    passengerForegroundPushSubscription =
        expressForegroundPushEvents().listen(_handleForegroundPushEvent);

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
        Timer.periodic(const Duration(milliseconds: 1400), (_) {
      unawaited(_refreshPassengerCriticalState());
    });
    unawaited(_refreshPassengerCriticalState());

    // Fuente independiente de ofertas: no depende del estado del Home.
    passengerLiveOfferTimer =
        Timer.periodic(const Duration(milliseconds: 900), (_) {
      unawaited(_refreshPassengerLiveOfferState());
    });
    unawaited(_refreshPassengerLiveOfferState());
  }

  Future<void> _refreshPassengerLiveOfferState() async {
    if (!mounted || passengerLiveOfferInFlight) return;
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
    nextFuture.whenComplete(() {
      if (!mounted) return;
      homeRefreshInFlight = false;
      if (homeRefreshQueued) {
        homeRefreshQueued = false;
        _refreshHome();
      }
    });
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

  Future<void> _locate() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      final position = await locationService.currentPosition();
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        current = point;
        pickup ??= PickedLocation(
          label: 'Mi ubicación actual',
          latitude: position.latitude,
          longitude: position.longitude,
        );
      });
      mapController.move(point, 15);
      // La primera carga ocurre antes de resolver el GPS. Refrescamos en
      // cuanto ya conocemos la posición para poblar los vehículos cercanos.
      _refreshHome();
    } catch (_) {
      // El mapa sigue disponible aunque el usuario no conceda GPS.
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
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/' +
            a.longitude.toString() +
            ',' +
            a.latitude.toString() +
            ';' +
            b.longitude.toString() +
            ',' +
            b.latitude.toString() +
            '?overview=full&geometries=geojson',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return;
      final first = routes.first;
      if (first is! Map) return;

      final distanceMeters = asDouble(first['distance']);
      final durationSeconds = asDouble(first['duration']);
      if (mounted && distanceMeters != null && durationSeconds != null) {
        setState(() {
          routeDistanceKm = distanceMeters / 1000;
          routeDurationMinutes =
              (durationSeconds / 60).clamp(1, 1440).round();
        });
      }

      final geometry = first['geometry'];
      if (geometry is! Map) return;
      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) return;

      final points = <LatLng>[];
      for (final raw in coordinates) {
        if (raw is List && raw.length >= 2) {
          final lng = raw[0];
          final lat = raw[1];
          if (lat is num && lng is num) {
            points.add(LatLng(lat.toDouble(), lng.toDouble()));
          }
        }
      }
      if (points.length < 2 || !mounted) return;

      setState(() => roadRoute = points);
      _fitRouteCamera(
        panelFraction: routeConfirmed
            ? .68
            : _routeConfirmationSheetFraction(context),
      );
    } catch (_) {
      // Mantener la línea directa como respaldo si el enrutador no responde.
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
    if (pickup == null || destination == null || routing) return;
    setState(() => routeConfirmed = true);
    _movePassengerSheet(.68);
    _fitRouteCamera(panelFraction: .68);
    await _refreshFareQuote();
  }

  Future<void> _refreshFareQuote() async {
    final distance = routeDistanceKm;
    final duration = routeDurationMinutes;
    if (destination == null || distance == null || duration == null) return;
    if (fareManuallyEdited) return;

    setState(() => quoting = true);
    try {
      final quote = await widget.service.quoteFare(
        serviceKey: category,
        distanceKm: distance,
        durationMinutes: duration,
      );
      final amount = quote['amount'];
      if (!mounted || amount is! num) return;
      setState(() => fare = amount);
    } catch (_) {
      // Se conserva la tarifa actual si el cotizador no responde.
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
  }

  Future<void> _ratePending(Map<String, dynamic> pending) async {
    final saved = await showExpressRatingDialog(
      context,
      widget.service,
      pending,
    );
    if (saved && mounted) {
      _refreshHome();
      widget.onChanged();
    }
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

    final pendingRating = cachedData?.pendingRating ??
        await widget.service.pendingRatingService();
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
    if (markerLat != null && markerLng != null) {
      try {
        final effectiveCategory =
            openRide?['category']?.toString() ?? category;
        final requestedVehicleType = effectiveCategory == 'motorcycle'
            ? 'motorcycle'
            : effectiveCategory == 'xl'
                ? 'xl'
                : 'car';

        nearbyDrivers = await widget.service.nearbyOnlineDriverMarkers(
          latitude: markerLat,
          longitude: markerLng,
          radiusKm: 10,
          vehicleType: requestedVehicleType,
        );
      } catch (_) {}
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
            labelText: 'Nueva oferta (Bs)',
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'El destino no puede ser la misma ubicación de recogida. Selecciona otra ubicación.',
              ),
            ),
          );
        return;
      }

      final createdRide = await runExpressStateTransition<Map<String, dynamic>>(
        context,
        processingTitle: 'Buscando conductores…',
        processingSubtitle: 'Estamos publicando tu solicitud.',
        successTitle: 'Buscando conductores',
        successSubtitle: 'Tu solicitud ya está visible para conductores cercanos.',
        eventName: 'RIDE_REQUEST_CREATED',
        action: () => widget.service.createRideRequest(
          category: category,
          pickupAddress: from.label,
          destinationAddress: to.label,
          proposedFare: fare,
          paymentMethod: payment,
          pickupLatitude: from.latitude,
          pickupLongitude: from.longitude,
          destinationLatitude: to.latitude,
          destinationLongitude: to.longitude,
          routeDistanceKm: routeDistanceKm,
          routeDurationMinutes: routeDurationMinutes,
          scheduledFor: scheduledFor,
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
        final height = MediaQuery.sizeOf(sheetContext).height;
        return SizedBox(
          height: height * .76,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 34),
            children: [
              const ListTile(
                leading: CircleAvatar(
                  backgroundColor: expressBlue,
                  child: Icon(Icons.bolt_rounded, color: Colors.white),
                ),
                title: Text(
                  'EXPRESS',
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
    passengerOfferBootstrapTimer?.cancel();
    passengerCriticalStateTimer?.cancel();
    passengerLiveOfferTimer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PassengerStateData>(
      future: homeFuture,
      builder: (context, snapshot) {
        final darkHome = _riderHomeDark(context);
        final confirmRouteFraction =
            _routeConfirmationSheetFraction(context);

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
                child: const _MapPin(
                  icon: Icons.my_location_rounded,
                  dark: false,
                ),
              ),
            );
          } else if (current != null) {
            markers.add(
              Marker(
                point: current!,
                width: 50,
                height: 50,
                child: const _MapPin(
                  icon: Icons.person_rounded,
                  dark: false,
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
                  width: 48,
                  height: 58,
                  child: _VehicleMapMarker(
                    vehicleType: driver['vehicle_type']?.toString() ?? 'car',
                    orientation: ((((lat.abs() * 1000) +
                                    (lng.abs() * 1000))
                                .round() %
                            9) -
                        4) *
                    .17,
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
                    initialZoom: current == null ? 13 : 15,
                  ),
                  children: [
                    if (darkHome)
                      ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          -0.17008, -0.57216, -0.05776, 0, 230,
                          -0.17008, -0.57216, -0.05776, 0, 230,
                          -0.17008, -0.57216, -0.05776, 0, 230,
                          0, 0, 0, 1, 0,
                        ]),
                        child: TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.express.delivery',
                        ),
                      )
                    else
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.express.delivery',
                      ),
                    if (lines.isNotEmpty) PolylineLayer(polylines: lines),
                    if (markers.isNotEmpty) MarkerLayer(markers: markers),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(
                          'OpenStreetMap contributors',
                        ),
                      ],
                    ),
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
                        icon: Icons.menu_rounded,
                        onPressed: _showPassengerMenu,
                      ),
                      const Spacer(),
                      _CircleButton(
                        icon: routing
                            ? Icons.route_rounded
                            : Icons.my_location_rounded,
                        onPressed: _locate,
                        busy: locating || routing,
                      ),
                    ],
                  ),
                ),
              ),
              if ((!initialLoading || snapshot.hasError) &&
                  effectivePassengerOffers.isEmpty)
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
                              ? .50
                              : destination == null
                                  ? .42
                                  : routeConfirmed
                                      ? .68
                                      : confirmRouteFraction,
                  minChildSize: hasPassengerOffers
                      ? .52
                      : (compactSearching || submittingRide)
                          ? .36
                          : hasActivePassengerService
                              ? .48
                              : destination == null
                                  ? .42
                                  : routeConfirmed
                                      ? .68
                                      : confirmRouteFraction,
                  maxChildSize: hasPassengerOffers
                      ? .92
                      : (compactSearching || submittingRide)
                          ? .68
                          : hasActivePassengerService
                              ? .78
                              : destination == null
                                  ? .42
                                  : routeConfirmed
                                      ? .68
                                      : confirmRouteFraction,
                  snap: compactSearching ||
                      submittingRide ||
                      hasPassengerOffers ||
                      hasActivePassengerService,
                  snapSizes: hasPassengerOffers
                      ? const [.52, .72, .92]
                      : (compactSearching || submittingRide)
                          ? const [.36, .42, .68]
                          : hasActivePassengerService
                              ? const [.48, .50, .78]
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

                    return _PassengerBottomPanel(
                      controller: scrollController,
                      data: data,
                    serviceType: serviceType,
                    category: category,
                    payment: payment,
                    fare: fare,
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
                      fare = value;
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
                },
              ),
              if (hasPassengerOffers)
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
  final ScrollController controller;
  final _PassengerStateData data;
  final String serviceType;
  final String category;
  final String payment;
  final num fare;
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
    required this.serviceType,
    required this.category,
    required this.payment,
    required this.fare,
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
            title: 'Buscando conductores…',
            subtitle:
                'Estamos publicando tu solicitud para conductores cercanos.',
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
        controller: controller,
        category: category,
        payment: payment,
        fare: fare,
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
        if (data.activeTrip != null)
          _PassengerActiveTripCard(
            trip: data.activeTrip!,
            driver: data.counterpart,
            driverProfile: data.driverProfile,
            vehicle: data.driverVehicle,
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
            onCall: () => callExpressNumber(
              context,
              data.counterpart?['phone']?.toString(),
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
                routing: routing,
                quoting: quoting,
              ),
            ],
            const SizedBox(height: 12),
            _RideOfferCard(
              fare: fare,
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
                  ? 'Bs ' + fare.toString()
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
                  ? 'Bs ' + fare.toString()
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
                  ? 'Bs ' + fare.toString()
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
                  ? 'Bs ' + fare.toString()
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
    final controller = TextEditingController(text: fare.toString());
    final result = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tu oferta'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Monto en Bs',
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
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) onFare(result);
  }

  Future<void> _chooseSchedule(BuildContext context) async {
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
          {
            'value': 'cash',
            'label': 'Efectivo',
            'icon': Icons.payments_rounded,
            'color': const Color(0xFF22C55E),
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
                        'Por el momento solo aceptamos efectivo. Tarjeta y Billetera Express se habilitarán desde administración.',
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
  final VoidCallback onServices;
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
    required this.onServices,
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
  Timer? timer;

  LatLng? current;
  bool busy = false;
  bool driverRefreshInFlight = false;
  _DriverStateData? cachedData;
  late Future<_DriverStateData> driverFuture;
  final ValueNotifier<LatLng?> driverPosition = ValueNotifier<LatLng?>(null);
  final Set<String> viewedRideRequestIds = <String>{};
  bool viewedRideRequestIdsLoaded = false;
  String? driverRequestPopupId;
  bool driverRequestPopupAutomatic = false;
  int driverRequestPopupRemaining = 0;
  Timer? driverRequestPopupTimer;
  String? driverOfferPendingRideId;
  int driverOfferPendingRemaining = 0;
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

  void _refreshDriverActiveRoadRoute(
    String tripId,
    String status,
    LatLng from,
    LatLng target,
  ) {
    final key = tripId + ':' + status + ':' +
        (from.latitude * 1000).round().toString() + ':' +
        (from.longitude * 1000).round().toString();
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

    // Respaldo de red: si push o Realtime se interrumpen, el conductor
    // consulta solicitudes disponibles sin depender del foco de Android.
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
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

  void _startTracking() {
    if (positionSubscription != null) return;
    positionSubscription = locationService.positionStream().listen(
      (position) async {
        current = LatLng(position.latitude, position.longitude);
        try {
          await widget.service.updateDriverDetails(
            latitude: position.latitude,
            longitude: position.longitude,
          );
        } catch (_) {}
        if (mounted) {
          driverPosition.value = current;
          if (cachedData?.activeTrip != null) setState(() {});
        }
      },
      onError: (_) {},
    );
  }

  Future<_DriverStateData> _load() async {
    final profile = await widget.service.myDriverProfile() ??
        await widget.service.ensureDriverProfile();
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

    List<Map<String, dynamic>> rides = [];
    List<Map<String, dynamic>> deliveries = [];
    if (profile['approval_status'] == 'approved' &&
        profile['online_status'] == 'online' &&
        activeTrip == null &&
        activeDelivery == null) {
      rides = await widget.service.availableRideRequests();
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
      try {
        final serverViewedIds =
            await widget.service.myViewedRideRequestIds();
        viewedRideRequestIds.addAll(serverViewedIds);
        viewedRideRequestIdsLoaded = true;
      } catch (_) {}
      _startTracking();
    }

    Map<String, dynamic>? counterpart;
    final counterpartId = activeTrip?['passenger_id']?.toString() ??
        activeDelivery?['customer_id']?.toString();
    if (counterpartId != null) {
      counterpart = await widget.service.userById(counterpartId);
    }

    final pendingRating = await widget.service.pendingRatingService();

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
    final requestCount = next.rides.length;
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
    );
    if (saved && mounted) {
      _reconcileDriverHomeInBackground();
      // No forzamos una recarga global aquí: el estado optimista ya refleja el
      // paso confirmado. El home se reconcilia en segundo plano.
      widget.onChanged();
    }
  }

  Future<void> _toggleOnline(Map<String, dynamic> profile) async {
    if (busy) return;
    final wasOnline = profile['online_status'] == 'online';
    setState(() => busy = true);

    try {
      if (wasOnline) {
        await widget.service.setDriverOnline(false);
        await positionSubscription?.cancel();
        positionSubscription = null;
      } else {
        final position = await locationService.currentPosition();
        final point = LatLng(position.latitude, position.longitude);
        await Future.wait<void>([
          widget.service.updateDriverDetails(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
          widget.service.setDriverOnline(true),
        ]);
        current = point;
        driverPosition.value = point;
        _startTracking();
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
                labelText: 'Tu tarifa (Bs)',
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
        return 'driver_arriving';
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
        return 'Ir al pasajero';
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

    String? pin;
    if (next == 'in_progress') {
      pin = await _askBoardingPin();
      if (pin == null || !mounted) return;
    }

    final processingTitle = switch (next) {
      'driver_arriving' => 'Preparando ruta…',
      'driver_waiting' => 'Confirmando llegada…',
      'in_progress' => 'Validando PIN…',
      'completed' => 'Finalizando viaje…',
      _ => 'Actualizando viaje…',
    };
    final successTitle = switch (next) {
      'driver_arriving' => 'Ruta iniciada',
      'driver_waiting' => 'Llegada confirmada',
      'in_progress' => 'Viaje iniciado',
      'completed' => 'Viaje completado',
      _ => 'Estado actualizado',
    };
    final successSubtitle = switch (next) {
      'driver_arriving' => 'El pasajero ya sabe que vas en camino.',
      'driver_waiting' => 'Avisamos al pasajero que ya llegaste.',
      'in_progress' => 'PIN correcto. El viaje está en curso.',
      'completed' => 'El viaje quedó finalizado correctamente.',
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
          // Para los pasos de ruta la UI ya avanzó de forma optimista antes
          // del RPC. El servidor sigue siendo autoritativo y el refresh
          // posterior confirma el estado.
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
                leading: const Icon(Icons.route_outlined),
                title: const Text('Servicios activos'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onServices();
                },
              ),
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

      final distanceKm = _pickupDistanceKm(
        current,
        asDouble(ride['pickup_latitude']),
        asDouble(ride['pickup_longitude']),
      );
      return distanceKm == null || distanceKm <= 10;
    }).toList();

    if (candidates.isEmpty) return;

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
      final coordinates = <String>[
        if (current != null)
          current!.longitude.toString() + ',' + current!.latitude.toString(),
        pickupLng.toString() + ',' + pickupLat.toString(),
        destinationLng.toString() + ',' + destinationLat.toString(),
      ];
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/' +
            coordinates.join(';') +
            '?overview=full&geometries=geojson',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return;
      final first = routes.first;
      if (first is! Map) return;
      final geometry = first['geometry'];
      if (geometry is! Map) return;
      final rawCoordinates = geometry['coordinates'];
      if (rawCoordinates is! List || rawCoordinates.length < 2) return;

      final points = <LatLng>[];
      for (final raw in rawCoordinates) {
        if (raw is List && raw.length >= 2) {
          final lng = raw[0];
          final lat = raw[1];
          if (lat is num && lng is num) {
            points.add(LatLng(lat.toDouble(), lng.toDouble()));
          }
        }
      }

      if (!mounted ||
          driverRequestPopupId != popupId ||
          points.length < 2) {
        return;
      }
      setState(() => driverPopupRoadRoute = points);
    } catch (_) {
      // Mantener la línea directa si el enrutador no responde.
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

    setState(() {
      driverRequestPopupId = id;
      driverRequestPopupAutomatic = automatic;
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

      if (driverRequestPopupRemaining <= 1) {
        timer.cancel();
        _closeDriverRequestPopup(showNext: true);
        return;
      }

      setState(() => driverRequestPopupRemaining--);
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
        driverPopupRoadRoute = const [];
      });
    } else {
      driverRequestPopupId = null;
      driverRequestPopupAutomatic = false;
      driverRequestPopupRemaining = 0;
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
        return SafeArea(
          top: false,
          child: Container(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
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
                    color: const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Solicitudes activas',
                          style: TextStyle(
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
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: rides.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay solicitudes activas.',
                            style: TextStyle(
                              color: expressMuted,
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

                            return Material(
                              color: const Color(0xFFF8FAFC),
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
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      const CircleAvatar(
                                        backgroundColor:
                                            Color(0xFFEAF2FF),
                                        child: Icon(
                                          Icons.local_taxi_rounded,
                                          color: expressBlue,
                                        ),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              pickup + ' → ' + destination,
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              [
                                                ride['category']
                                                        ?.toString() ??
                                                    'Viaje',
                                                if (distanceLabel.isNotEmpty)
                                                  distanceLabel,
                                              ].join(' · '),
                                              style: const TextStyle(
                                                color: expressMuted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Bs ' +
                                                amount.toStringAsFixed(2),
                                            style: const TextStyle(
                                              color: expressBlue,
                                              fontWeight:
                                                  FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: expressMuted,
                                          ),
                                        ],
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
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.express.delivery',
                    ),
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
                              child: const _MapPin(
                                icon: Icons.local_taxi_rounded,
                                dark: false,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (markers.isNotEmpty) MarkerLayer(markers: markers),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
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
                      ),
                      const Spacer(),
                      _ModeBadge(
                        icon: Icons.drive_eta_rounded,
                        text: 'Conductor',
                        onPressed: widget.onSwitchMode,
                      ),
                      const SizedBox(width: 8),
                      if (data != null)
                        _OnlineBadge(
                          approved:
                              data.profile['approval_status'] == 'approved',
                          online: data.profile['online_status'] == 'online',
                          busy: busy,
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
                            onTripTracking: _openTripTracking,
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
                color: Colors.white,
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
                  const Text(
                    'Esperando confirmación del pasajero',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tu oferta ya fue enviada. Mientras esperas no recibirás ni podrás aceptar otra solicitud.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: expressMuted,
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
    final pickup = ride['pickup_address']?.toString() ?? 'Origen';
    final destination =
        ride['destination_address']?.toString() ?? 'Destino';
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
                            'Bs ${fare.toStringAsFixed(2)}',
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
                          'Aceptar por Bs ${fare.toStringAsFixed(2)}',
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
                                  '+ Bs ${(amount - fare).toStringAsFixed(0)}',
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
      bottomPadding: 6,
      children: [
        if (data.pendingRating != null) ...[
          _PendingRatingCard(
            pending: data.pendingRating!,
            onTap: () => onRatePending(data.pendingRating!),
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
            onCall: () => callExpressNumber(
              context,
              data.counterpart?['phone']?.toString(),
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
          _DriverRequestsButton(
            count: data.rides.length,
            onTap: onRequests,
          ),
          const SizedBox(height: 10),
          if (data.rides.isEmpty)
            const _NoticeCard(
              icon: Icons.radar_rounded,
              title: 'Esperando solicitudes…',
              subtitle:
                  'Cuando llegue un viaje, el detalle se abrirá automáticamente.',
            )
          else
            const _NoticeCard(
              icon: Icons.notifications_active_outlined,
              title: 'Buscando viajes cerca',
              subtitle:
                  'La solicitud prioritaria aparece arriba. Toca “Solicitudes” para ver todas.',
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
    return Material(
      color: Colors.white,
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
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.inbox_rounded,
                  color: expressBlue,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitudes',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Ver solicitudes activas',
                      style: TextStyle(
                        color: expressMuted,
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
                      : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  count.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: count > 0 ? Colors.white : expressMuted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: expressMuted,
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
  final bool routing;
  final bool quoting;
  final bool showFare;

  const _RouteSummary({
    required this.distanceKm,
    required this.durationMinutes,
    required this.fare,
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
                    text: 'Sugerido Bs ' + fare.toString(),
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

  const _PendingRatingCard({
    required this.pending,
    required this.onTap,
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
                        ? 'Califica tu último delivery'
                        : 'Califica tu último viaje',
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
      child: ListView(
        controller: controller,
        shrinkWrap: controller == null,
        primary: false,
        physics: controller == null
            ? const ClampingScrollPhysics()
            : null,
        padding: EdgeInsets.fromLTRB(
          16,
          6,
          16,
          bottomPadding ?? 18 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
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
        ],
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
  final ScrollController controller;
  final String category;
  final String payment;
  final num fare;
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
    required this.controller,
    required this.category,
    required this.payment,
    required this.fare,
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

  String get selectedLabel {
    switch (category) {
      case 'comfort':
        return 'Comfort';
      case 'xl':
        return 'XL';
      case 'motorcycle':
        return 'Moto';
      default:
        return 'Express';
    }
  }

  IconData get selectedIcon {
    switch (category) {
      case 'comfort':
        return Icons.local_taxi_rounded;
      case 'xl':
        return Icons.airport_shuttle_rounded;
      case 'motorcycle':
        return Icons.two_wheeler_rounded;
      default:
        return Icons.directions_car_filled_rounded;
    }
  }

  int get selectedSeats {
    switch (category) {
      case 'xl':
        return 6;
      case 'motorcycle':
        return 1;
      default:
        return 4;
    }
  }

  String _durationText() {
    final minutes = routeDurationMinutes;
    return minutes == null ? 'Calculando tiempo' : minutes.toString() + ' min';
  }

  void _changeFare(double delta) {
    if (quoting) return;
    final next = (fare.toDouble() + delta).clamp(1.0, 9999.0);
    onFare(double.parse(next.toStringAsFixed(2)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = _riderHomeDark(context);
    final surface = dark ? const Color(0xFF121212) : Colors.white;
    final footer = dark ? const Color(0xFF151515) : const Color(0xFFFDFDFD);

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
                    child: Text(
                      'Elige tu viaje',
                      style: TextStyle(
                        color: _riderText(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
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
                quoting: quoting,
                onEdit: onEditFare,
                onDecrease: () => _changeFare(-0.50),
                onIncrease: () => _changeFare(0.50),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                children: [
                  Text(
                    'Servicios disponibles',
                    style: TextStyle(
                      color: _riderMuted(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  _RideChoiceCard(
                    selected: category == 'economy',
                    icon: Icons.directions_car_filled_rounded,
                    title: 'Express',
                    subtitle: '4 pasajeros · ' + _durationText() +
                        ' · Viaje económico',
                    price: category == 'economy' && !quoting
                        ? 'Bs ' + fare.toString()
                        : null,
                    onTap: () => onCategory('economy'),
                  ),
                  const SizedBox(height: 6),
                  _RideChoiceCard(
                    selected: category == 'comfort',
                    icon: Icons.local_taxi_rounded,
                    title: 'Comfort',
                    subtitle: '4 pasajeros · ' + _durationText() +
                        ' · Más comodidad',
                    price: category == 'comfort' && !quoting
                        ? 'Bs ' + fare.toString()
                        : null,
                    onTap: () => onCategory('comfort'),
                  ),
                  const SizedBox(height: 6),
                  _RideChoiceCard(
                    selected: category == 'xl',
                    icon: Icons.airport_shuttle_rounded,
                    title: 'XL',
                    subtitle: '6 pasajeros · ' + _durationText() +
                        ' · Más espacio',
                    price: category == 'xl' && !quoting
                        ? 'Bs ' + fare.toString()
                        : null,
                    onTap: () => onCategory('xl'),
                  ),
                  const SizedBox(height: 6),
                  _RideChoiceCard(
                    selected: category == 'motorcycle',
                    icon: Icons.two_wheeler_rounded,
                    title: 'Moto',
                    subtitle: '1 pasajero · ' + _durationText() +
                        ' · Más ágil',
                    price: category == 'motorcycle' && !quoting
                        ? 'Bs ' + fare.toString()
                        : null,
                    onTap: () => onCategory('motorcycle'),
                  ),
                  const SizedBox(height: 10),
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
                      onPressed: creating || quoting ? null : onCreate,
                      icon: creating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.local_taxi_rounded),
                      label: Text('Confirmar ' + selectedLabel),
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

class _RideFareControlCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final int seats;
  final String durationText;
  final num fare;
  final bool quoting;
  final VoidCallback onEdit;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _RideFareControlCard({
    required this.icon,
    required this.title,
    required this.seats,
    required this.durationText,
    required this.fare,
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
                            : 'Bs ' + fare.toString(),
                        style: TextStyle(
                          color: _riderText(context),
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Tu oferta',
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
  final bool quoting;
  final VoidCallback onTap;

  const _RideOfferCard({
    required this.fare,
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
                quoting ? '…' : 'Bs ' + fare.toString(),
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

  const _SearchRoundDecisionDialog({
    required this.currentFare,
  });

  @override
  State<_SearchRoundDecisionDialog> createState() =>
      _SearchRoundDecisionDialogState();
}

class _SearchRoundDecisionDialogState
    extends State<_SearchRoundDecisionDialog> {
  Timer? timer;
  int remaining = 30;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (remaining <= 1) {
        timer?.cancel();
        Navigator.pop(context, 'cancel');
        return;
      }
      setState(() => remaining--);
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
            'Oferta actual: Bs ${widget.currentFare.toStringAsFixed(2)}',
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
    if (elapsed < 18) {
      title = 'Buscando conductores';
      subtitle = 'Enviando tu solicitud a conductores cercanos';
    } else if (elapsed < 36) {
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
    if (elapsed < 18) {
      title = 'Buscando conductores';
      subtitle = 'Enviando tu solicitud a conductores cercanos';
    } else if (elapsed < 36) {
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
  final int remainingSeconds;
  final double? passengerFare;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _PassengerDriverOfferCard({
    required this.offer,
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
                'Bs ${fare.toStringAsFixed(2)}',
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
                    '${remainingSeconds.clamp(0, 15)} s',
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
                      'Bs ' + (widget.offer['proposed_fare']?.toString() ?? '-'),
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
    final pickup = ride['pickup_address']?.toString() ?? 'Origen';
    final destination =
        ride['destination_address']?.toString() ?? 'Destino';
    final fare = asDouble(trip['final_fare']);
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
                  'Bs ${fare.toStringAsFixed(2)}',
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
    return (300 - elapsed).clamp(0, 300);
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: passengerOnWay
            ? const Color(0xFFEAFBF3)
            : expired
                ? const Color(0xFFFFF1F0)
                : const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: passengerOnWay
              ? const Color(0xFFABEFC6)
              : expired
                  ? const Color(0xFFFDA29B)
                  : const Color(0xFFFEDC89),
        ),
      ),
      child: Row(
        children: [
          Icon(
            passengerOnWay
                ? Icons.directions_walk_rounded
                : Icons.timer_outlined,
            color: passengerOnWay
                ? const Color(0xFF067647)
                : expired
                    ? const Color(0xFFB42318)
                    : const Color(0xFFB54708),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              passengerOnWay
                  ? 'El pasajero avisó “Ya voy”. Tiempo de abordaje: $clock'
                  : expired
                      ? 'Se cumplió el tiempo de cortesía de 5 minutos.'
                      : 'Al pasajero le quedan $clock para abordar.',
              style: const TextStyle(
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
                  backgroundColor: const Color(0xFFEAF2FF),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E7EC)),
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
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: expressMuted),
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

  const _CircleButton({
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      color: _riderHomeDark(context)
          ? const Color(0xFF151515)
          : Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: busy ? null : onPressed,
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
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onPressed;

  const _ModeBadge({
    required this.icon,
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: expressBlue, size: 18),
              const SizedBox(width: 6),
              Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.swap_horiz_rounded, size: 17),
            ],
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
  final VoidCallback onPressed;

  const _OnlineBadge({
    required this.approved,
    required this.online,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final active = approved && online;
    return Material(
      elevation: 5,
      color: active ? const Color(0xFF12B76A) : Colors.white,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: busy ? null : onPressed,
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

  const _VehicleMapMarker({
    required this.vehicleType,
    this.orientation = 0,
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
          child: Transform.rotate(
            angle: widget.orientation,
            child: child,
          ),
        );
      },
      child: Container(
        width: 40,
        height: 52,
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
      final cx = size.width / 2;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + 1.5, size.height / 2 + 3),
          width: 14,
          height: 38,
        ),
        shadow,
      );
      canvas.drawCircle(Offset(cx, 8), 5.2, dark);
      canvas.drawCircle(Offset(cx, size.height - 8), 5.2, dark);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 6, 11, 12, size.height - 22),
          const Radius.circular(6),
        ),
        body,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 4, 19, 8, 13),
          const Radius.circular(4),
        ),
        glass,
      );
      canvas.drawCircle(Offset(cx, 14), 2.4, light);
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
      return 'Ir al pasajero';
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
  return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
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
    case 'pagorut':
      return 'PagoRUT';
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

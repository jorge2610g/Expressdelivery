Warning: truncated output (original token count: 164291)
Total output lines: 18614

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
import 'cancellation_debt_messages.dart';
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
    final debtMessage = cancellationDebtActionMessage(error, driver: true);
    state.value = _ExpressTransitionView(
      phase: _ExpressTransitionPhase.error,
      title: debtMessage == null ? 'No se pudo completar' : 'Deuda pendiente',
      subtitle: debtMessage ?? 'Revisa la conexión e inténtalo nuevamente.',
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
  …156291 tokens truncated… const Color(0xFFDDE5EF);

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

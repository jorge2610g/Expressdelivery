import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'connected_center.dart';
import 'location_picker.dart';
import 'location_service.dart';
import 'service_tracking.dart';
import 'services/express_service.dart';

const Color expressBlue = Color(0xFF0B57D0);
const Color expressDark = Color(0xFF101828);
const Color expressMuted = Color(0xFF667085);
const LatLng expressFallback = LatLng(-14.8333, -64.9000);

double? asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
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
  List<LatLng> roadRoute = const [];
  _PassengerStateData? cachedData;
  late Future<_PassengerStateData> homeFuture;
  int loadRevision = 0;
  int panelRevision = 0;
  Timer? timer;
  Timer? passengerOfferTimer;
  String? passengerOfferId;
  int passengerOfferRemaining = 0;
  final Set<String> presentedPassengerOfferIds = <String>{};
  final Set<String> renewalPromptedRideIds = <String>{};
  bool renewalDecisionOpen = false;
  String? renewalDecisionRideId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final initial = widget.initialState;
    if (initial != null) {
      cachedData = _passengerDataFromRawState(initial);
      homeFuture = Future.value(cachedData!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshHome();
      });
    } else {
      homeFuture = _load(++loadRevision);
    }

    _locate();
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _refreshHome();
    });
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

  void _refreshHome() {
    final revision = ++loadRevision;
    setState(() {
      homeFuture = _load(revision);
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

    final pendingRating = await widget.service.pendingRatingService();
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
    final activeOffers = listOfMaps(state['offers']).where((offer) {
      if (offer['status']?.toString() != 'pending') return false;
      final expiresAt =
          DateTime.tryParse(offer['expires_at']?.toString() ?? '')?.toUtc();
      return expiresAt == null || expiresAt.isAfter(now);
    }).toList();

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
      driverProfile: mapOrNull(state['driver_profile']),
      pendingRating: pendingRating,
      viewedCount: viewedCount,
      viewers: viewers,
      nearbyDrivers: nearbyDrivers,
    );

    if (revision != loadRevision) return next;

    cachedData = next;

    if (rideCancellationConfirmed) cancellingRideId = null;
    if (tripCancellationConfirmed) cancellingTripId = null;
    if (deliveryCancellationConfirmed) cancellingDeliveryId = null;

    _tryAutoAcceptOffers(
      activeOffers,
      openRide,
    );

    if (autoAcceptNearest) {
      _clearPassengerOfferPopup();
    } else {
      _syncPassengerOfferPopup(next);
    }
    _maybePromptSearchRenewal(next);

    return next;
  }

  void _clearPassengerOfferPopup() {
    passengerOfferTimer?.cancel();
    passengerOfferTimer = null;
    if (!mounted) {
      passengerOfferId = null;
      passengerOfferRemaining = 0;
      return;
    }
    if (passengerOfferId != null || passengerOfferRemaining != 0) {
      setState(() {
        passengerOfferId = null;
        passengerOfferRemaining = 0;
      });
    }
  }

  void _syncPassengerOfferPopup(_PassengerStateData data) {
    if (!mounted ||
        autoAcceptNearest ||
        data.activeTrip != null ||
        data.openRide == null) {
      _clearPassengerOfferPopup();
      return;
    }

    final validIds = data.offers
        .map((offer) => offer['id']?.toString())
        .whereType<String>()
        .toSet();

    if (passengerOfferId != null && validIds.contains(passengerOfferId)) {
      return;
    }

    passengerOfferTimer?.cancel();
    passengerOfferTimer = null;
    passengerOfferId = null;
    passengerOfferRemaining = 0;

    final queue = data.offers.where((offer) {
      final id = offer['id']?.toString();
      return id != null &&
          id.isNotEmpty &&
          !presentedPassengerOfferIds.contains(id);
    }).toList();

    queue.sort((a, b) {
      final aTime =
          DateTime.tryParse(a['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          DateTime.tryParse(b['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });

    if (queue.isEmpty) return;

    final offer = queue.first;
    final id = offer['id'].toString();
    final expiresAt =
        DateTime.tryParse(offer['expires_at']?.toString() ?? '')?.toUtc();
    final remaining = expiresAt == null
        ? 15
        : expiresAt
            .difference(DateTime.now().toUtc())
            .inSeconds
            .clamp(1, 15);

    presentedPassengerOfferIds.add(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || autoAcceptNearest) return;
      setState(() {
        passengerOfferId = id;
        passengerOfferRemaining = remaining;
      });
      passengerOfferTimer?.cancel();
      passengerOfferTimer =
          Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || passengerOfferId != id) {
          timer.cancel();
          return;
        }
        if (passengerOfferRemaining <= 1) {
          timer.cancel();
          unawaited(_expirePassengerOffer(offer));
          return;
        }
        setState(() => passengerOfferRemaining--);
      });
    });
  }

  Future<void> _expirePassengerOffer(Map<String, dynamic> offer) async {
    final id = offer['id']?.toString();
    if (id == null || id.isEmpty) return;
    if (passengerOfferId == id) {
      _clearPassengerOfferPopup();
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
    _clearPassengerOfferPopup();
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

    if (value) {
      _clearPassengerOfferPopup();
      if (data != null) {
        _tryAutoAcceptOffers(data.offers, data.openRide);
      }
      return;
    }

    if (data != null) {
      _syncPassengerOfferPopup(data);
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
    });

    await _fitRoute();
    await _refreshFareQuote();
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

    setState(() => creating = true);
    try {
      final createdRide = await widget.service.createRideRequest(
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
    _clearPassengerOfferPopup();
    try {
      await widget.service.selectRideOffer(offer['id'].toString());
      if (!mounted) return;
      _refreshHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aceptar la oferta: ' + e.toString())),
      );
    }
  }

  Future<void> _declineOffer(Map<String, dynamic> offer) async {
    _clearPassengerOfferPopup();
    try {
      await widget.service.declineRideOffer(offer['id'].toString());
      if (!mounted) return;
      _refreshHome();
    } catch (_) {
      if (!mounted) return;
      _refreshHome();
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
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    passengerOfferTimer?.cancel();
    mapController.dispose();
    sheetController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
        final initialLoading = data == null;
        final compactSearching = data != null &&
            data.openRide != null &&
            !_isScheduledLater(data.openRide!) &&
            data.offers.isEmpty;
        final searchingNow = data != null &&
            data.openRide != null &&
            !_isScheduledLater(data.openRide!);
        final markers = <Marker>[];
        final lines = <Polyline>[];

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
                child: const IgnorePointer(
                  child: _MapSearchRadar(),
                ),
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
              if (!initialLoading || snapshot.hasError)
                DraggableScrollableSheet(
                  key: ValueKey(
                    (compactSearching ? 'passenger-searching-' : 'passenger-home-') +
                        panelRevision.toString(),
                  ),
                  controller: sheetController,
                  initialChildSize: compactSearching
                      ? .36
                      : destination == null
                          ? .42
                          : routeConfirmed
                              ? .68
                              : confirmRouteFraction,
                  minChildSize: compactSearching
                      ? .28
                      : destination == null
                          ? .42
                          : routeConfirmed
                              ? .68
                              : confirmRouteFraction,
                  maxChildSize: compactSearching
                      ? .62
                      : destination == null
                          ? .42
                          : routeConfirmed
                              ? .68
                              : confirmRouteFraction,
                  snap: compactSearching,
                  snapSizes: compactSearching
                      ? const [.28, .36, .62]
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
          _ActiveCard(
            icon: Icons.local_taxi_rounded,
            title: data.counterpart?['full_name']?.toString().trim().isNotEmpty == true
                ? data.counterpart!['full_name'].toString()
                : 'Conductor asignado',
            subtitle: _tripStatus(data.activeTrip!['status']?.toString()),
            detail: data.driverProfile?['vehicle_summary']?.toString(),
            rating: data.driverProfile?['rating']?.toString(),
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
            dangerLabel: ['driver_assigned', 'driver_arriving', 'driver_waiting']
                    .contains(data.activeTrip!['status']?.toString())
                ? 'Cancelar'
                : null,
            onDanger: ['driver_assigned', 'driver_arriving', 'driver_waiting']
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
          _OffersCard(
            ride: data.openRide!,
            offers: data.offers,
            viewedCount: data.viewedCount,
            viewers: data.viewers,
            nearbyCount: data.nearbyDrivers.length,
            autoAcceptNearest: autoAcceptNearest,
            onAutoAcceptNearest: onAutoAcceptNearest,
            onOffer: onOffer,
            onDecline: onDeclineOffer,
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
          {
            'value': 'pagorut',
            'label': 'PagoRUT',
            'icon': Icons.account_balance_rounded,
            'color': const Color(0xFFF97316),
          },
          {
            'value': 'mercado_pago',
            'label': 'Mercado Pago',
            'icon': Icons.handshake_rounded,
            'color': const Color(0xFF38BDF8),
          },
          {
            'value': 'santander',
            'label': 'Banco Santander',
            'icon': Icons.local_fire_department_rounded,
            'color': const Color(0xFFEF4444),
          },
          {
            'value': 'mach',
            'label': 'MACH',
            'icon': Icons.change_history_rounded,
            'color': const Color(0xFF7C3AED),
          },
          {
            'value': 'tenpo',
            'label': 'Tenpo',
            'icon': Icons.account_balance_wallet_rounded,
            'color': const Color(0xFF111827),
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
                        'Solo indica cómo pagarás al conductor. Express no procesa estos pagos.',
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
  final VoidCallback onEarnings;
  final VoidCallback onProfile;
  final VoidCallback onSafety;

  const DriverMapHome({
    super.key,
    required this.service,
    required this.revision,
    required this.onChanged,
    required this.onSwitchMode,
    required this.onServices,
    required this.onEarnings,
    required this.onProfile,
    required this.onSafety,
  });

  @override
  State<DriverMapHome> createState() => _DriverMapHomeState();
}

class _DriverMapHomeState extends State<DriverMapHome> {
  final mapController = MapController();
  final locationService = const ExpressLocationService();
  StreamSubscription? positionSubscription;
  Timer? timer;

  LatLng? current;
  bool busy = false;
  _DriverStateData? cachedData;
  int refresh = 0;

  @override
  void initState() {
    super.initState();
    _locate();
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => refresh++);
    });
  }

  Future<void> _locate() async {
    try {
      final position = await locationService.currentPosition();
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => current = point);
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
        if (mounted) setState(() {});
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
      try {
        await widget.service.markRideRequestsViewed(
          rides
              .map((row) => row['id']?.toString())
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList(),
        );
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
    return next;
  }

  Future<void> _ratePending(Map<String, dynamic> pending) async {
    final saved = await showExpressRatingDialog(
      context,
      widget.service,
      pending,
    );
    if (saved && mounted) {
      setState(() => refresh++);
      widget.onChanged();
    }
  }

  Future<void> _toggleOnline(Map<String, dynamic> profile) async {
    setState(() => busy = true);
    try {
      final online = profile['online_status'] == 'online';
      if (online) {
        await widget.service.setDriverOnline(false);
        await positionSubscription?.cancel();
        positionSubscription = null;
      } else {
        final position = await locationService.currentPosition();
        await widget.service.updateDriverDetails(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        current = LatLng(position.latitude, position.longitude);
        await widget.service.setDriverOnline(true);
        _startTracking();
      }
      if (!mounted) return;
      setState(() => refresh++);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => busy = false);
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
      await widget.service.createRideOffer(
        rideRequestId: ride['id'].toString(),
        fare: amount,
        etaMinutes: eta,
      );
      if (!mounted) return;
      setState(() => refresh++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oferta enviada al pasajero.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo ofertar: ' + e.toString())),
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
      await widget.service.createRideOffer(
        rideRequestId: ride['id'].toString(),
        fare: amount,
        etaMinutes: eta,
      );
      if (!mounted) return;
      setState(() => refresh++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tarifa de Bs ' +
                amount.toStringAsFixed(2) +
                ' aceptada. Esperando confirmación del pasajero.',
          ),
        ),
      );
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
      setState(() => refresh++);
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
    final next = _nextTripStatus(trip['status']?.toString());
    if (next == null) return;
    try {
      await widget.service.advanceTrip(trip['id'].toString(), next);
      if (!mounted) return;
      setState(() => refresh++);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo avanzar: ' + e.toString())),
      );
    }
  }

  Future<void> _advanceDelivery(Map<String, dynamic> delivery) async {
    final next = _nextDeliveryStatus(delivery['status']?.toString());
    if (next == null) return;
    try {
      await widget.service.advanceDelivery(delivery['id'].toString(), next);
      if (!mounted) return;
      setState(() => refresh++);
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
      setState(() => refresh++);
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
      setState(() => refresh++);
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

  @override
  void dispose() {
    timer?.cancel();
    positionSubscription?.cancel();
    mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DriverStateData>(
      key: ValueKey(widget.revision.toString() + '-' + refresh.toString()),
      future: _load(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? cachedData;
        final markers = <Marker>[];

        if (current != null) {
          markers.add(
            Marker(
              point: current!,
              width: 52,
              height: 52,
              child: const _MapPin(
                icon: Icons.local_taxi_rounded,
                dark: false,
              ),
            ),
          );
        }

        if (data != null) {
          for (final row in data.rides.take(10)) {
            final lat = asDouble(row['pickup_latitude']);
            final lng = asDouble(row['pickup_longitude']);
            if (lat != null && lng != null) {
              markers.add(
                Marker(
                  point: LatLng(lat, lng),
                  width: 42,
                  height: 42,
                  child: const _MapPin(
                    icon: Icons.person_pin_circle_rounded,
                    dark: true,
                  ),
                ),
              );
            }
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
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.express.delivery',
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
                top: 10,
                left: 14,
                right: 14,
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
              DraggableScrollableSheet(
                key: ValueKey(
                  data?.activeTrip != null || data?.activeDelivery != null
                      ? 'driver-sheet-active'
                      : 'driver-sheet-idle',
                ),
                initialChildSize: data?.activeTrip != null ||
                        data?.activeDelivery != null
                    ? .48
                    : .42,
                minChildSize: data?.activeTrip != null ||
                        data?.activeDelivery != null
                    ? .34
                    : .30,
                maxChildSize: .72,
                snap: true,
                snapSizes: data?.activeTrip != null ||
                        data?.activeDelivery != null
                    ? const [.34, .48, .72]
                    : const [.30, .42, .72],
                builder: (context, controller) {
                  if (snapshot.connectionState ==
                          ConnectionState.waiting &&
                      data == null) {
                    return _PanelShell(
                      controller: controller,
                      children: const [
                        Center(child: CircularProgressIndicator()),
                      ],
                    );
                  }
                  if (snapshot.hasError || data == null) {
                    return _PanelShell(
                      controller: controller,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 42),
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
                    controller: controller,
                    data: data,
                    current: current,
                    onToggle: () => _toggleOnline(data.profile),
                    onRide: _offerRide,
                    onAcceptRideFare: _acceptRideAtPassengerFare,
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
            ],
          ),
        );
      },
    );
  }
}

class _DriverBottomPanel extends StatelessWidget {
  final ScrollController controller;
  final _DriverStateData data;
  final LatLng? current;
  final VoidCallback onToggle;
  final ValueChanged<Map<String, dynamic>> onRide;
  final ValueChanged<Map<String, dynamic>> onAcceptRideFare;
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
    required this.current,
    required this.onToggle,
    required this.onRide,
    required this.onAcceptRideFare,
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
      children: [
        if (data.pendingRating != null) ...[
          _PendingRatingCard(
            pending: data.pendingRating!,
            onTap: () => onRatePending(data.pendingRating!),
          ),
          const SizedBox(height: 10),
        ],
        if (data.activeTrip != null)
          _ActiveCard(
            icon: Icons.local_taxi_rounded,
            title: data.counterpart?['full_name']?.toString().trim().isNotEmpty == true
                ? data.counterpart!['full_name'].toString()
                : 'Pasajero',
            subtitle: _tripStatus(data.activeTrip!['status']?.toString()),
            detail: 'Pasajero del viaje',
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
            dangerLabel: ['driver_assigned', 'driver_arriving', 'driver_waiting']
                    .contains(data.activeTrip!['status']?.toString())
                ? 'Cancelar'
                : null,
            onDanger: ['driver_assigned', 'driver_arriving', 'driver_waiting']
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
          const _NoticeCard(
            icon: Icons.power_settings_new_rounded,
            title: 'Estás fuera de línea',
            subtitle:
                'Ponte en línea para ver viajes cerca de ti.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: onToggle,
              icon: const Icon(Icons.power_settings_new_rounded),
              label: const Text('Ponerme en línea'),
            ),
          ),
        ] else ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Solicitudes cerca de ti',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                data.rides.length.toString(),
                style: const TextStyle(
                  color: expressBlue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (data.rides.isEmpty)
            const _NoticeCard(
              icon: Icons.radar_rounded,
              title: 'Esperando solicitudes…',
              subtitle:
                  'Las nuevas solicitudes aparecerán automáticamente.',
            ),
          ...data.rides.map(
            (row) => _JobCard(
              icon: Icons.local_taxi_rounded,
              route: (row['pickup_address']?.toString() ?? 'Origen') +
                  ' → ' +
                  (row['destination_address']?.toString() ?? 'Destino'),
              fare: 'Bs ' + (row['proposed_fare']?.toString() ?? '-'),
              badge: row['category']?.toString() ?? 'Viaje',
              button: 'Aceptar tarifa',
              secondaryButton: 'Ofertar otro monto',
              onSecondary: () => onRide(row),
              pickupDistanceKm: _pickupDistanceKm(
                current,
                asDouble(row['pickup_latitude']),
                asDouble(row['pickup_longitude']),
              ),
              routeDistanceKm: asDouble(row['route_distance_km']),
              routeDurationMinutes:
                  (row['route_duration_minutes'] as num?)?.toInt(),
              paymentMethod: row['payment_method']?.toString(),
              onTap: () => onAcceptRideFare(row),
            ),
          ),

        ],
      ],
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
  final ScrollController controller;
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
        padding: EdgeInsets.fromLTRB(
          16,
          6,
          16,
          bottomPadding ?? 18 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
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
  final VoidCallback onCancel;

  const _OffersCard({
    required this.ride,
    required this.offers,
    required this.viewedCount,
    required this.viewers,
    required this.nearbyCount,
    required this.autoAcceptNearest,
    required this.onAutoAcceptNearest,
    required this.onOffer,
    required this.onDecline,
    required this.onCancel,
  });

  @override
  State<_OffersCard> createState() => _OffersCardState();
}

class _OffersCardState extends State<_OffersCard> {
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
    final createdAt =
        DateTime.tryParse(widget.ride['created_at']?.toString() ?? '')?.toUtc();
    final expiresAt =
        DateTime.tryParse(widget.ride['expires_at']?.toString() ?? '')?.toUtc();
    final elapsed = createdAt == null
        ? 0
        : now.difference(createdAt).inSeconds.clamp(0, 9999);
    final remaining = expiresAt == null
        ? 0
        : expiresAt.difference(now).inSeconds.clamp(0, 9999);
    final total = createdAt == null || expiresAt == null
        ? 0
        : expiresAt.difference(createdAt).inSeconds;
    final progress = total <= 0
        ? null
        : (remaining / total).clamp(0.0, 1.0).toDouble();

    String title;
    String subtitle;
    if (widget.offers.isNotEmpty) {
      title = 'Elige un conductor';
      subtitle = widget.offers.length == 1
          ? 'Tienes 1 oferta disponible'
          : 'Tienes ${widget.offers.length} ofertas disponibles';
    } else if (elapsed < 18) {
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
        if (widget.offers.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...widget.offers.map(
            (offer) => _ExpiringRideOfferCard(
              offer: offer,
              onChoose: () => widget.onOffer(offer),
              onDecline: () => widget.onDecline(offer),
            ),
          ),
        ],
      ],
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
        ? 20
        : expiresAt.difference(DateTime.now().toUtc()).inSeconds;
    if (!mounted) return;
    setState(() => remaining = next.clamp(0, 20).toInt());
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

    return Container(
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
              Icon(
                Icons.circle,
                size: 10,
                color: active ? Colors.white : const Color(0xFF98A2B3),
              ),
              const SizedBox(width: 6),
              Text(
                !approved
                    ? 'Pendiente'
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

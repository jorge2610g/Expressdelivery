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
  String selected = reasons.first;
  final controller = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocalState) => AlertDialog(
        title: Text('Cancelar ' + serviceLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: reasons
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setLocalState(() => selected = value);
                }
              },
            ),
            if (selected == 'Otro motivo') ...[
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Describe el motivo',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancelar servicio'),
          ),
        ],
      ),
    ),
  );

  final custom = controller.text.trim();
  controller.dispose();
  if (confirmed != true) return null;
  if (selected == 'Otro motivo' && custom.isNotEmpty) return custom;
  return selected;
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

class PassengerMapHome extends StatefulWidget {
  final ExpressService service;
  final VoidCallback onChanged;
  final VoidCallback onSwitchMode;
  final VoidCallback onHistory;
  final VoidCallback onPayments;
  final VoidCallback onProfile;
  final VoidCallback onSavedPlaces;
  final VoidCallback onSafety;

  const PassengerMapHome({
    super.key,
    required this.service,
    required this.onChanged,
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

class _PassengerMapHomeState extends State<PassengerMapHome> {
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
  double? routeDistanceKm;
  int? routeDurationMinutes;
  List<LatLng> roadRoute = const [];
  _PassengerStateData? cachedData;
  late Future<_PassengerStateData> homeFuture;
  bool showInitialVerifier = false;
  Timer? verifierTimer;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    homeFuture = _load();
    _scheduleInitialVerifier();
    _locate();
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _refreshHome();
    });
  }

  void _scheduleInitialVerifier() {
    verifierTimer?.cancel();
    showInitialVerifier = false;
    verifierTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted && cachedData == null) {
        setState(() => showInitialVerifier = true);
      }
    });
  }

  void _refreshHome({bool showVerifierIfEmpty = false}) {
    if (showVerifierIfEmpty && cachedData == null) {
      _scheduleInitialVerifier();
    }
    setState(() {
      homeFuture = _load();
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
          title: serviceType == 'ride'
              ? 'Seleccionar origen'
              : 'Seleccionar recogida',
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
    _movePassengerSheet(.50);
    await _fitRoute();
  }

  Future<void> _pickDestination() async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: serviceType == 'ride'
              ? '¿A dónde vas?'
              : '¿Dónde entregamos?',
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
    _movePassengerSheet(.50);
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

    mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(from, to),
        padding: const EdgeInsets.fromLTRB(42, 100, 42, 360),
      ),
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
    _movePassengerSheet(.58);
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
        serviceKey: serviceType == 'delivery' ? 'delivery' : category,
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

  Future<_PassengerStateData> _load() async {
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

    final next = _PassengerStateData(
      service: widget.service,
      openRide: mapOrNull(state['open_ride']),
      activeTrip: mapOrNull(state['active_trip']),
      activeDelivery: mapOrNull(state['active_delivery']),
      offers: listOfMaps(state['offers']),
      saved: listOfMaps(state['saved']),
      counterpart: mapOrNull(state['counterpart']),
      driverProfile: mapOrNull(state['driver_profile']),
      pendingRating: pendingRating,
    );

    cachedData = next;
    return next;
  }

  Future<void> _createService() async {
    final from = pickup;
    final to = destination;
    if (from == null || to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona origen y destino.')),
      );
      return;
    }

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
      if (serviceType == 'ride') {
        await widget.service.createRideRequest(
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
      } else {
        await widget.service.createDelivery(
          packageType: 'package',
          pickupAddress: from.label,
          dropoffAddress: to.label,
          proposedFare: fare,
          paymentMethod: payment,
          pickupLatitude: from.latitude,
          pickupLongitude: from.longitude,
          dropoffLatitude: to.latitude,
          dropoffLongitude: to.longitude,
          routeDistanceKm: routeDistanceKm,
          routeDurationMinutes: routeDurationMinutes,
        );
      }

      if (!mounted) return;
      setState(() {
        destination = null;
        routeConfirmed = false;
        scheduledFor = null;
        routeDistanceKm = null;
        routeDurationMinutes = null;
        roadRoute = const [];
        fareManuallyEdited = false;
      });
      _refreshHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el servicio: ' + e.toString())),
      );
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> _selectOffer(Map<String, dynamic> offer) async {
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

  Future<void> _cancelOpenRide(Map<String, dynamic> ride) async {
    final reason = await askExpressCancellationReason(context, 'solicitud');
    if (reason == null || !mounted) return;
    try {
      await widget.service.cancelRideRequest(
        ride['id'].toString(),
        reason: reason,
      );
      if (!mounted) return;
      _refreshHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: ' + e.toString())),
      );
    }
  }

  Future<void> _cancelActiveTrip(Map<String, dynamic> trip) async {
    final reason = await askExpressCancellationReason(context, 'viaje');
    if (reason == null || !mounted) return;
    try {
      await widget.service.cancelTrip(
        trip['id'].toString(),
        reason: reason,
      );
      if (!mounted) return;
      _refreshHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: ' + e.toString())),
      );
    }
  }

  Future<void> _cancelActiveDelivery(Map<String, dynamic> delivery) async {
    final reason = await askExpressCancellationReason(context, 'delivery');
    if (reason == null || !mounted) return;
    try {
      await widget.service.cancelDelivery(
        delivery['id'].toString(),
        reason: reason,
      );
      if (!mounted) return;
      _refreshHome();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: ' + e.toString())),
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
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                subtitle: Text('Viajes · Delivery'),
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
        ),
      ),
    );
  }

  @override
  void dispose() {
    verifierTimer?.cancel();
    timer?.cancel();
    mapController.dispose();
    sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PassengerStateData>(
      future: homeFuture,
      builder: (context, snapshot) {
        final darkHome = _riderHomeDark(context);
        final data = snapshot.data ?? cachedData;
        final initialLoading = data == null;
        final markers = <Marker>[];
        final lines = <Polyline>[];

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

        if (destination != null) {
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

        if (pickup != null && destination != null) {
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
          bottomNavigationBar: !initialLoading &&
                  data != null &&
                  data.activeTrip == null &&
                  data.activeDelivery == null &&
                  data.openRide == null
              ? _PassengerFixedServiceBar(
                  selected: serviceType,
                  onChanged: (value) {
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
                  },
                )
              : null,
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
              if (!initialLoading ||
                  showInitialVerifier ||
                  snapshot.hasError)
                DraggableScrollableSheet(
                  controller: sheetController,
                  initialChildSize: .50,
                  minChildSize: .50,
                  maxChildSize: .92,
                  snap: true,
                  snapSizes: const [.50, .58, .92],
                  builder: (context, scrollController) {
                    if (initialLoading) {
                      return _PassengerInitialPanel(
                        controller: scrollController,
                        hasError: snapshot.hasError,
                        error: snapshot.error,
                        onRetry: () =>
                            _refreshHome(showVerifierIfEmpty: true),
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
                    },
                    onCategory: (value) {
                      setState(() {
                        category = value;
                        fareManuallyEdited = false;
                      });
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
                      _movePassengerSheet(.50);
                    },
                    onCreate: _createService,
                    onOffer: _selectOffer,
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
                      _movePassengerSheet(.50);
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
        if (!hasError) ...[
          const _NoticeCard(
            icon: Icons.sync_rounded,
            title: 'Verificando tu servicio…',
            subtitle:
                'Estamos comprobando si tienes un viaje o delivery activo antes de mostrar opciones.',
          ),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ] else ...[
          const _NoticeCard(
            icon: Icons.error_outline_rounded,
            title: 'No pudimos verificar tu servicio',
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
    return _PanelShell(
      controller: controller,
      darkSurface: _riderHomeDark(context),
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
            onOffer: onOffer,
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
              serviceType == 'ride' ? '¿A dónde vas?' : '¿Qué quieres enviar?',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
                color: _riderText(context),
                height: 1.02,
              ),
            ),
            const SizedBox(height: 11),
            _HomeDestinationSearch(
              serviceType: serviceType,
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
            const SizedBox(height: 13),
            Row(
              children: [
                const Expanded(
                  child: _RiderSectionTitle('Viajes recientes'),
                ),
                TextButton(
                  onPressed: onHistory,
                  child: const Text('Ver todos'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _RecentTripsPreview(
              service: data.service,
              onHistory: onHistory,
            ),
            const SizedBox(height: 12),
          ] else if (!routeConfirmed) ...[
            Text(
              serviceType == 'ride'
                  ? 'Confirma tu ruta'
                  : 'Confirma tu envío',
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
                label: Text(
                  serviceType == 'ride'
                      ? 'Confirmar ruta y continuar'
                      : 'Confirmar puntos y continuar',
                ),
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
                    serviceType == 'ride'
                        ? 'Elige tu viaje'
                        : 'Elige tu delivery',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: _riderText(context),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onReviewRoute,
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 17),
                  label: const Text('Revisar ruta'),
                ),
              ],
            ),
            if (routeDistanceKm != null &&
                routeDurationMinutes != null) ...[
              const SizedBox(height: 8),
              _RouteSummary(
                distanceKm: routeDistanceKm!,
                durationMinutes: routeDurationMinutes!,
                fare: fare,
                routing: routing,
                quoting: quoting,
              ),
            ],
            const SizedBox(height: 14),
            if (serviceType == 'ride') ...[
              SizedBox(
                height: 86,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _CategoryTile(
                      selected: category == 'economy',
                      icon: Icons.directions_car_rounded,
                      title: 'Express',
                      subtitle: 'Económico',
                      onTap: () => onCategory('economy'),
                    ),
                    _CategoryTile(
                      selected: category == 'comfort',
                      icon: Icons.airline_seat_recline_extra_rounded,
                      title: 'Comfort',
                      subtitle: 'Cómodo',
                      onTap: () => onCategory('comfort'),
                    ),
                    _CategoryTile(
                      selected: category == 'xl',
                      icon: Icons.airport_shuttle_rounded,
                      title: 'XL',
                      subtitle: 'Más espacio',
                      onTap: () => onCategory('xl'),
                    ),
                    _CategoryTile(
                      selected: category == 'motorcycle',
                      icon: Icons.two_wheeler_rounded,
                      title: 'Moto',
                      subtitle: 'Rápido',
                      onTap: () => onCategory('motorcycle'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _MiniSetting(
                icon: Icons.schedule_rounded,
                label: 'Cuándo',
                value: scheduledFor == null
                    ? 'Ahora'
                    : _formatSchedule(scheduledFor!),
                onTap: () => _chooseSchedule(context),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: _MiniSetting(
                    icon: Icons.payments_outlined,
                    label: 'Tu oferta',
                    value: quoting ? 'Calculando…' : 'Bs ' + fare.toString(),
                    onTap: quoting ? () {} : () => _editFare(context),
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
            const SizedBox(height: 8),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: creating || quoting ? null : onCreate,
                icon: creating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        serviceType == 'ride'
                            ? Icons.local_taxi_rounded
                            : Icons.local_shipping_rounded,
                      ),
                label: Text(
                  serviceType == 'ride'
                      ? 'Buscar conductores'
                      : 'Buscar repartidor',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: expressBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Efectivo'),
              trailing:
                  payment == 'cash' ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(sheetContext, 'cash'),
            ),
            ListTile(
              leading: const Icon(Icons.credit_card_rounded),
              title: const Text('Tarjeta'),
              trailing:
                  payment == 'card' ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(sheetContext, 'card'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Billetera Express'),
              trailing:
                  payment == 'wallet' ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(sheetContext, 'wallet'),
            ),
          ],
        ),
      ),
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
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
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
      deliveries = await widget.service.availableDeliveries();
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
                subtitle: Text('Viajes · Delivery'),
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
          for (final row in data.deliveries.take(10)) {
            final lat = asDouble(row['pickup_latitude']);
            final lng = asDouble(row['pickup_longitude']);
            if (lat != null && lng != null) {
              markers.add(
                Marker(
                  point: LatLng(lat, lng),
                  width: 42,
                  height: 42,
                  child: const _MapPin(
                    icon: Icons.inventory_2_rounded,
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
                initialChildSize: data?.activeTrip != null ||
                        data?.activeDelivery != null
                    ? .38
                    : .31,
                minChildSize: .23,
                maxChildSize: .60,
                snap: true,
                snapSizes: const [.23, .42, .60],
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
                'Ponte en línea para ver viajes y delivery cerca de ti.',
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
                (data.rides.length + data.deliveries.length).toString(),
                style: const TextStyle(
                  color: expressBlue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (data.rides.isEmpty && data.deliveries.isEmpty)
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
              button: 'Ofertar',
              pickupDistanceKm: _pickupDistanceKm(
                current,
                asDouble(row['pickup_latitude']),
                asDouble(row['pickup_longitude']),
              ),
              routeDistanceKm: asDouble(row['route_distance_km']),
              routeDurationMinutes:
                  (row['route_duration_minutes'] as num?)?.toInt(),
              paymentMethod: row['payment_method']?.toString(),
              onTap: () => onRide(row),
            ),
          ),
          ...data.deliveries.map(
            (row) => _JobCard(
              icon: Icons.local_shipping_rounded,
              route: (row['pickup_address']?.toString() ?? 'Origen') +
                  ' → ' +
                  (row['dropoff_address']?.toString() ?? 'Destino'),
              fare: 'Bs ' + (row['proposed_fare']?.toString() ?? '-'),
              badge: row['package_type']?.toString() ?? 'Delivery',
              button: 'Aceptar',
              pickupDistanceKm: _pickupDistanceKm(
                current,
                asDouble(row['pickup_latitude']),
                asDouble(row['pickup_longitude']),
              ),
              routeDistanceKm: asDouble(row['route_distance_km']),
              routeDurationMinutes:
                  (row['route_duration_minutes'] as num?)?.toInt(),
              paymentMethod: row['payment_method']?.toString(),
              onTap: () => onDelivery(row),
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
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCFE0FF)),
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
          style: const TextStyle(
            color: expressDark,
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

  const _PanelShell({
    required this.controller,
    required this.children,
    this.darkSurface = false,
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
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
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
        padding: const EdgeInsets.all(14),
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
        width: 112,
        margin: const EdgeInsets.only(right: 9),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? expressBlue : const Color(0xFFE4E7EC),
            width: selected ? 1.7 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: expressBlue, size: 28),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                color: expressMuted,
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E7EC)),
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
                    style: const TextStyle(
                      fontSize: 10,
                      color: expressMuted,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w900),
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
        const SizedBox(height: 10),
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

class _OffersCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final List<Map<String, dynamic>> offers;
  final ValueChanged<Map<String, dynamic>> onOffer;
  final VoidCallback onCancel;

  const _OffersCard({
    required this.ride,
    required this.offers,
    required this.onOffer,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _NoticeCard(
          icon: Icons.radar_rounded,
          title: 'Buscando conductores…',
          subtitle: 'Las ofertas aparecerán aquí.',
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancelar búsqueda'),
          ),
        ),
        if (offers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            offers.length.toString() +
                (offers.length == 1 ? ' oferta recibida' : ' ofertas recibidas'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...offers.map(
            (offer) {
              final rawDriver = offer['driver_profiles'];
              final driver = rawDriver is Map
                  ? Map<String, dynamic>.from(rawDriver)
                  : <String, dynamic>{};
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: expressBlue,
                      child: Icon(Icons.person_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bs ' + (offer['proposed_fare']?.toString() ?? '-'),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '★ ' +
                                (driver['rating']?.toString() ?? '5.0') +
                                ' · ' +
                                (offer['eta_minutes']?.toString() ?? '?') +
                                ' min',
                            style: const TextStyle(color: expressMuted),
                          ),
                          Text(
                            driver['vehicle_summary']?.toString() ??
                                'Vehículo por confirmar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: expressMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: offer['status'] == 'pending'
                          ? () => onOffer(offer)
                          : null,
                      child: const Text('Elegir'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
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
    case 'card':
      return 'Tarjeta';
    case 'wallet':
      return 'Billetera';
    default:
      return 'Efectivo';
  }
}

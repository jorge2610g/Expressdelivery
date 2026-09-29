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

class PassengerMapHome extends StatefulWidget {
  final ExpressService service;
  final VoidCallback onChanged;
  final VoidCallback onSwitchMode;
  final VoidCallback onHistory;
  final VoidCallback onPayments;
  final VoidCallback onProfile;

  const PassengerMapHome({
    super.key,
    required this.service,
    required this.onChanged,
    required this.onSwitchMode,
    required this.onHistory,
    required this.onPayments,
    required this.onProfile,
  });

  @override
  State<PassengerMapHome> createState() => _PassengerMapHomeState();
}

class _PassengerMapHomeState extends State<PassengerMapHome> {
  final mapController = MapController();
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
  List<LatLng> roadRoute = const [];
  _PassengerStateData? cachedData;
  int refresh = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _locate();
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) setState(() => refresh++);
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
    setState(() => pickup = result);
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
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => destination = result);
    await _fitRoute();
  }

  Future<void> _fitRoute() async {
    final a = pickup;
    final b = destination;
    if (a == null || b == null) {
      if (mounted) setState(() => roadRoute = const []);
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

    setState(() {
      routing = true;
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
      if (mounted) setState(() => routing = false);
    }
  }

  Future<_PassengerStateData> _load() async {
    final rides = await widget.service.myRideRequests();
    final trips = await widget.service.myTrips();
    final deliveries = await widget.service.myDeliveries();
    final saved = await widget.service.savedAddresses();

    Map<String, dynamic>? openRide;
    for (final row in rides) {
      final status = row['status']?.toString();
      if (status == 'searching' || status == 'offers_received') {
        openRide = row;
        break;
      }
    }

    Map<String, dynamic>? activeTrip;
    for (final row in trips) {
      final status = row['status']?.toString();
      if (status != 'completed' && status != 'cancelled') {
        activeTrip = row;
        break;
      }
    }

    Map<String, dynamic>? activeDelivery;
    for (final row in deliveries) {
      final status = row['status']?.toString();
      if (status != 'delivered' && status != 'cancelled') {
        activeDelivery = row;
        break;
      }
    }

    List<Map<String, dynamic>> offers = [];
    if (openRide != null) {
      offers = await widget.service.offersForRide(openRide['id'].toString());
    }

    Map<String, dynamic>? counterpart;
    Map<String, dynamic>? driverProfile;

    final activeDriverId = activeTrip?['driver_id']?.toString() ??
        activeDelivery?['courier_id']?.toString();
    if (activeDriverId != null) {
      counterpart = await widget.service.userById(activeDriverId);
      driverProfile =
          await widget.service.driverProfileById(activeDriverId);
    }

    final next = _PassengerStateData(
      service: widget.service,
      openRide: openRide,
      activeTrip: activeTrip,
      activeDelivery: activeDelivery,
      offers: offers,
      saved: saved,
      counterpart: counterpart,
      driverProfile: driverProfile,
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
        );
      }

      if (!mounted) return;
      setState(() {
        destination = null;
        scheduledFor = null;
        refresh++;
      });
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
      setState(() => refresh++);
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
      setState(() => refresh++);
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
      setState(() => refresh++);
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
      setState(() => refresh++);
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
    timer?.cancel();
    mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PassengerStateData>(
      key: ValueKey(refresh),
      future: _load(),
      builder: (context, snapshot) {
        final data =
            snapshot.data ?? cachedData ?? _PassengerStateData(service: widget.service);
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
                    if (lines.isNotEmpty) PolylineLayer(polylines: lines),
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
                        onPressed: _showPassengerMenu,
                      ),
                      const Spacer(),
                      _ModeBadge(
                        icon: Icons.person_rounded,
                        text: 'Pasajero',
                        onPressed: widget.onSwitchMode,
                      ),
                      const SizedBox(width: 8),
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
              DraggableScrollableSheet(
                initialChildSize: _panelSize(data),
                minChildSize: .23,
                maxChildSize: .72,
                snap: true,
                snapSizes: const [.23, .42, .72],
                builder: (context, scrollController) {
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
                    creating: creating,
                    onType: (value) {
                      setState(() {
                        serviceType = value;
                        fare = value == 'ride' ? 5 : 8;
                        scheduledFor = null;
                        destination = null;
                      });
                    },
                    onCategory: (value) => setState(() => category = value),
                    onPayment: (value) => setState(() => payment = value),
                    onFare: (value) => setState(() => fare = value),
                    onSchedule: (value) =>
                        setState(() => scheduledFor = value),
                    onPickup: _pickPickup,
                    onDestination: _pickDestination,
                    onCreate: _createService,
                    onOffer: _selectOffer,
                    onCancelRide: _cancelOpenRide,
                    onCancelTrip: _cancelActiveTrip,
                    onCancelDelivery: _cancelActiveDelivery,
                    onTripTracking: _openTripTracking,
                    onDeliveryTracking: _openDeliveryTracking,
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
                      });
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

  double _panelSize(_PassengerStateData data) {
    if (data.activeTrip != null ||
        data.activeDelivery != null ||
        data.openRide != null ||
        destination != null) {
      return .42;
    }
    return .30;
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
  final bool creating;
  final ValueChanged<String> onType;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onPayment;
  final ValueChanged<num> onFare;
  final ValueChanged<DateTime?> onSchedule;
  final VoidCallback onPickup;
  final VoidCallback onDestination;
  final VoidCallback onCreate;
  final ValueChanged<Map<String, dynamic>> onOffer;
  final ValueChanged<Map<String, dynamic>> onCancelRide;
  final ValueChanged<Map<String, dynamic>> onCancelTrip;
  final ValueChanged<Map<String, dynamic>> onCancelDelivery;
  final ValueChanged<Map<String, dynamic>> onTripTracking;
  final ValueChanged<Map<String, dynamic>> onDeliveryTracking;
  final ValueChanged<Map<String, dynamic>> onSaved;

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
    required this.creating,
    required this.onType,
    required this.onCategory,
    required this.onPayment,
    required this.onFare,
    required this.onSchedule,
    required this.onPickup,
    required this.onDestination,
    required this.onCreate,
    required this.onOffer,
    required this.onCancelRide,
    required this.onCancelTrip,
    required this.onCancelDelivery,
    required this.onTripTracking,
    required this.onDeliveryTracking,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      controller: controller,
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
          Row(
            children: [
              Expanded(
                child: _ToggleTile(
                  selected: serviceType == 'ride',
                  icon: Icons.local_taxi_rounded,
                  text: 'Viaje',
                  onTap: () => onType('ride'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToggleTile(
                  selected: serviceType == 'delivery',
                  icon: Icons.local_shipping_rounded,
                  text: 'Delivery',
                  onTap: () => onType('delivery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            serviceType == 'ride' ? '¿A dónde vas?' : '¿Dónde entregamos?',
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: expressDark,
            ),
          ),
          const SizedBox(height: 14),
          _AddressTile(
            icon: Icons.trip_origin_rounded,
            text: pickup?.label ?? 'Elegir punto de partida',
            onTap: onPickup,
          ),
          const SizedBox(height: 8),
          _AddressTile(
            icon: Icons.location_on_rounded,
            text: destination?.label ?? 'Buscar destino',
            onTap: onDestination,
            prominent: destination == null,
          ),
          if (destination == null && data.saved.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Lugares guardados',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: data.saved.length > 5 ? 5 : data.saved.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final row = data.saved[index];
                  return ActionChip(
                    avatar: const Icon(Icons.bookmark_outline_rounded),
                    label: Text(row['label']?.toString() ?? 'Lugar'),
                    onPressed: () => onSaved(row),
                  );
                },
              ),
            ),
          ],
          if (destination != null) ...[
            const SizedBox(height: 16),
            if (serviceType == 'ride') ...[
              const Text(
                'Elige tu servicio',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
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
            ],
            const SizedBox(height: 12),
            if (serviceType == 'ride') ...[
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
                    value: 'Bs ' + fare.toString(),
                    onTap: () => _editFare(context),
                  ),
                ),
                const SizedBox(width: 10),
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
            const SizedBox(height: 14),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: creating ? null : onCreate,
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

  const DriverMapHome({
    super.key,
    required this.service,
    required this.revision,
    required this.onChanged,
    required this.onSwitchMode,
    required this.onServices,
    required this.onEarnings,
    required this.onProfile,
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

    final next = _DriverStateData(
      service: widget.service,
      profile: profile,
      rides: rides,
      deliveries: deliveries,
      activeTrip: activeTrip,
      activeDelivery: activeDelivery,
      counterpart: counterpart,
    );
    cachedData = next;
    return next;
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
                maxChildSize: .72,
                snap: true,
                snapSizes: const [.23, .42, .72],
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
                    onToggle: () => _toggleOnline(data.profile),
                    onRide: _offerRide,
                    onDelivery: _claimDelivery,
                    onTripTracking: _openTripTracking,
                    onDeliveryTracking: _openDeliveryTracking,
                    onAdvanceTrip: _advanceTrip,
                    onAdvanceDelivery: _advanceDelivery,
                    onCancelTrip: _cancelDriverTrip,
                    onCancelDelivery: _cancelDriverDelivery,
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
  final VoidCallback onToggle;
  final ValueChanged<Map<String, dynamic>> onRide;
  final ValueChanged<Map<String, dynamic>> onDelivery;
  final ValueChanged<Map<String, dynamic>> onTripTracking;
  final ValueChanged<Map<String, dynamic>> onDeliveryTracking;
  final ValueChanged<Map<String, dynamic>> onAdvanceTrip;
  final ValueChanged<Map<String, dynamic>> onAdvanceDelivery;
  final ValueChanged<Map<String, dynamic>> onCancelTrip;
  final ValueChanged<Map<String, dynamic>> onCancelDelivery;

  const _DriverBottomPanel({
    required this.controller,
    required this.data,
    required this.onToggle,
    required this.onRide,
    required this.onDelivery,
    required this.onTripTracking,
    required this.onDeliveryTracking,
    required this.onAdvanceTrip,
    required this.onAdvanceDelivery,
    required this.onCancelTrip,
    required this.onCancelDelivery,
  });

  @override
  Widget build(BuildContext context) {
    final approved = data.profile['approval_status'] == 'approved';
    final online = data.profile['online_status'] == 'online';

    return _PanelShell(
      controller: controller,
      children: [
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
              onTap: () => onDelivery(row),
            ),
          ),
        ],
      ],
    );
  }
}

class _PanelShell extends StatelessWidget {
  final ScrollController controller;
  final List<Widget> children;

  const _PanelShell({
    required this.controller,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D5DD),
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
              ? const Color(0xFFF2F4F7)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E7EC)),
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
                  color: prominent ? expressDark : expressMuted,
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
  final VoidCallback onTap;

  const _JobCard({
    required this.icon,
    required this.route,
    required this.fare,
    required this.badge,
    required this.button,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
          CircleAvatar(
            backgroundColor: const Color(0xFFEAF2FF),
            child: Icon(icon, color: expressBlue),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  fare + ' · ' + badge,
                  style: const TextStyle(color: expressMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onTap,
            child: Text(button),
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
      color: Colors.white,
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
                : Icon(icon),
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

  const _PassengerStateData({
    required this.service,
    this.openRide,
    this.activeTrip,
    this.activeDelivery,
    this.offers = const [],
    this.saved = const [],
    this.counterpart,
    this.driverProfile,
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

  const _DriverStateData({
    required this.service,
    required this.profile,
    this.rides = const [],
    this.deliveries = const [],
    this.activeTrip,
    this.activeDelivery,
    this.counterpart,
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

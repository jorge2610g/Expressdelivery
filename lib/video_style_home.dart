import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

class PassengerMapHome extends StatefulWidget {
  final ExpressService service;
  final VoidCallback onChanged;
  final VoidCallback onSwitchMode;

  const PassengerMapHome({
    super.key,
    required this.service,
    required this.onChanged,
    required this.onSwitchMode,
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
  bool locating = false;
  bool creating = false;
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
    _fitRoute();
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
    _fitRoute();
  }

  void _fitRoute() {
    final a = pickup;
    final b = destination;
    if (a == null || b == null) return;
    mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(a.latitude, a.longitude),
          LatLng(b.latitude, b.longitude),
        ),
        padding: const EdgeInsets.fromLTRB(42, 100, 42, 360),
      ),
    );
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

    return _PassengerStateData(
      openRide: openRide,
      activeTrip: activeTrip,
      activeDelivery: activeDelivery,
      offers: offers,
      saved: saved,
    );
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
        final data = snapshot.data ?? const _PassengerStateData();
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
          lines.add(
            Polyline(
              points: [
                LatLng(pickup!.latitude, pickup!.longitude),
                LatLng(destination!.latitude, destination!.longitude),
              ],
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
                        onPressed: widget.onSwitchMode,
                      ),
                      const Spacer(),
                      _ModeBadge(
                        icon: Icons.person_rounded,
                        text: 'Pasajero',
                        onPressed: widget.onSwitchMode,
                      ),
                      const SizedBox(width: 8),
                      _CircleButton(
                        icon: Icons.my_location_rounded,
                        onPressed: _locate,
                        busy: locating,
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
                    pickup: pickup,
                    destination: destination,
                    creating: creating,
                    onType: (value) {
                      setState(() {
                        serviceType = value;
                        fare = value == 'ride' ? 5 : 8;
                        destination = null;
                      });
                    },
                    onCategory: (value) => setState(() => category = value),
                    onPayment: (value) => setState(() => payment = value),
                    onFare: (value) => setState(() => fare = value),
                    onPickup: _pickPickup,
                    onDestination: _pickDestination,
                    onCreate: _createService,
                    onOffer: _selectOffer,
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
  final PickedLocation? pickup;
  final PickedLocation? destination;
  final bool creating;
  final ValueChanged<String> onType;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onPayment;
  final ValueChanged<num> onFare;
  final VoidCallback onPickup;
  final VoidCallback onDestination;
  final VoidCallback onCreate;
  final ValueChanged<Map<String, dynamic>> onOffer;
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
    required this.pickup,
    required this.destination,
    required this.creating,
    required this.onType,
    required this.onCategory,
    required this.onPayment,
    required this.onFare,
    required this.onPickup,
    required this.onDestination,
    required this.onCreate,
    required this.onOffer,
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
            title: 'Viaje activo',
            subtitle: _tripStatus(data.activeTrip!['status']?.toString()),
            onMap: () => onTripTracking(data.activeTrip!),
          )
        else if (data.activeDelivery != null &&
            data.activeDelivery!['courier_id'] != null)
          _ActiveCard(
            icon: Icons.local_shipping_rounded,
            title: 'Delivery activo',
            subtitle:
                _deliveryStatus(data.activeDelivery!['status']?.toString()),
            onMap: () => onDeliveryTracking(data.activeDelivery!),
          )
        else if (data.openRide != null)
          _OffersCard(
            ride: data.openRide!,
            offers: data.offers,
            onOffer: onOffer,
          )
        else if (data.activeDelivery != null)
          const _NoticeCard(
            icon: Icons.radar_rounded,
            title: 'Buscando repartidor…',
            subtitle: 'La solicitud está activa y se actualizará automáticamente.',
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

  const DriverMapHome({
    super.key,
    required this.service,
    required this.revision,
    required this.onChanged,
    required this.onSwitchMode,
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

    return _DriverStateData(
      profile: profile,
      rides: rides,
      deliveries: deliveries,
      activeTrip: activeTrip,
      activeDelivery: activeDelivery,
    );
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
        final data = snapshot.data;
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
                        onPressed: widget.onSwitchMode,
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

  const _DriverBottomPanel({
    required this.controller,
    required this.data,
    required this.onToggle,
    required this.onRide,
    required this.onDelivery,
    required this.onTripTracking,
    required this.onDeliveryTracking,
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
            title: 'Viaje activo',
            subtitle: _tripStatus(data.activeTrip!['status']?.toString()),
            onMap: () => onTripTracking(data.activeTrip!),
          )
        else if (data.activeDelivery != null)
          _ActiveCard(
            icon: Icons.local_shipping_rounded,
            title: 'Delivery activo',
            subtitle:
                _deliveryStatus(data.activeDelivery!['status']?.toString()),
            onMap: () => onDeliveryTracking(data.activeDelivery!),
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

class _OffersCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final List<Map<String, dynamic>> offers;
  final ValueChanged<Map<String, dynamic>> onOffer;

  const _OffersCard({
    required this.ride,
    required this.offers,
    required this.onOffer,
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
  final VoidCallback onMap;

  const _ActiveCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onMap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1739), expressBlue],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFFDCEAFF)),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: onMap,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: expressBlue,
            ),
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
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
  final Map<String, dynamic>? openRide;
  final Map<String, dynamic>? activeTrip;
  final Map<String, dynamic>? activeDelivery;
  final List<Map<String, dynamic>> offers;
  final List<Map<String, dynamic>> saved;

  const _PassengerStateData({
    this.openRide,
    this.activeTrip,
    this.activeDelivery,
    this.offers = const [],
    this.saved = const [],
  });
}

class _DriverStateData {
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> rides;
  final List<Map<String, dynamic>> deliveries;
  final Map<String, dynamic>? activeTrip;
  final Map<String, dynamic>? activeDelivery;

  const _DriverStateData({
    required this.profile,
    this.rides = const [],
    this.deliveries = const [],
    this.activeTrip,
    this.activeDelivery,
  });
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

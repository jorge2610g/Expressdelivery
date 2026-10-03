import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'core/supabase_client.dart';

class ServiceTrackingPage extends StatefulWidget {
  final String title;
  final String status;
  final String driverId;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;

  const ServiceTrackingPage({
    super.key,
    required this.title,
    required this.status,
    required this.driverId,
    this.pickupLatitude,
    this.pickupLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
  });

  @override
  State<ServiceTrackingPage> createState() => _ServiceTrackingPageState();
}

class _ServiceTrackingPageState extends State<ServiceTrackingPage> {
  double mapZoom = 14;

  double _markerScale() {
    if (mapZoom >= 14) return 1;
    return (0.48 + ((mapZoom - 8) * 0.087)).clamp(0.48, 1.0);
  }

  double? _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.pickupLatitude != null && widget.pickupLongitude != null
        ? LatLng(widget.pickupLatitude!, widget.pickupLongitude!)
        : null;
    final destination =
        widget.destinationLatitude != null && widget.destinationLongitude != null
            ? LatLng(widget.destinationLatitude!, widget.destinationLongitude!)
            : null;

    if (pickup == null && destination == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Este servicio fue creado sin coordenadas. Los nuevos servicios pueden seleccionar origen y destino desde el mapa.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final initialCenter = pickup ?? destination!;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Estado: ${_statusLabel(widget.status)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('driver_profiles')
            .stream(primaryKey: ['id'])
            .eq('id', widget.driverId),
        builder: (context, snapshot) {
          final driver = snapshot.data?.isNotEmpty == true
              ? snapshot.data!.first
              : null;
          final driverLat = _number(driver?['latitude']);
          final driverLng = _number(driver?['longitude']);
          final driverPoint = driverLat != null && driverLng != null
              ? LatLng(driverLat, driverLng)
              : null;

          final beforePickup = const {
            'driver_assigned',
            'driver_arriving',
          }.contains(status);
          final waitingAtPickup = status == 'driver_waiting';
          final inTrip = status == 'in_progress' || status == 'emergency';

          final routePoints = <LatLng>[];
          if (beforePickup && driverPoint != null && pickup != null) {
            routePoints.addAll([driverPoint, pickup]);
          } else if (inTrip && driverPoint != null && destination != null) {
            routePoints.addAll([driverPoint, destination]);
          }

          double? distanceKm;
          int? etaMinutes;
          if (beforePickup && driverPoint != null && pickup != null) {
            distanceKm = const Distance().as(
              LengthUnit.Kilometer,
              driverPoint,
              pickup,
            );
            etaMinutes = (distanceKm * 3).ceil().clamp(1, 30).toInt();
          } else if (inTrip && driverPoint != null && destination != null) {
            distanceKm = const Distance().as(
              LengthUnit.Kilometer,
              driverPoint,
              destination,
            );
            etaMinutes = (distanceKm * 2.5).ceil().clamp(1, 60).toInt();
          }

          return Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: driverPoint ?? initialCenter,
                  initialZoom: 14,
                  onPositionChanged: (camera, hasGesture) {
                    final nextZoom = camera.zoom;
                    if ((nextZoom - mapZoom).abs() >= .15 && mounted) {
                      setState(() => mapZoom = nextZoom);
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.express.delivery',
                  ),
                  if (routePoints.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routePoints,
                          strokeWidth: 5,
                          color: const Color(0xFF0B57D0),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      // Antes de recoger: solo conductor + punto de recogida.
                      if (beforePickup && pickup != null)
                        Marker(
                          point: pickup,
                          width: 48,
                          height: 48,
                          child: const _MapMarker(
                            icon: Icons.trip_origin_rounded,
                            label: 'Recogida',
                          ),
                        ),
                      // Durante el viaje: conductor + destino. Nunca usamos la
                      // ubicación GPS del pasajero como origen de esta etapa.
                      if (inTrip && destination != null)
                        Marker(
                          point: destination,
                          width: 48,
                          height: 48,
                          child: const _MapMarker(
                            icon: Icons.location_on_rounded,
                            label: 'Destino',
                          ),
                        ),
                      // Al llegar al punto no dibujamos ruta ni puntos extra:
                      // el conductor ya está en la recogida.
                      if (!waitingAtPickup && driverPoint != null)
                        Marker(
                          point: driverPoint,
                          width: 38 * _markerScale(),
                          height: 38 * _markerScale(),
                          child: Transform.scale(
                            scale: _markerScale(),
                            child: const _MapMarker(
                              icon: Icons.two_wheeler_rounded,
                              label: 'Conductor',
                              driver: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('OpenStreetMap contributors'),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: SafeArea(
                  top: false,
                  child: Card(
                    elevation: 6,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              driverPoint == null
                                  ? Icons.location_searching_rounded
                                  : Icons.two_wheeler_rounded,
                              color: const Color(0xFF0B57D0),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _statusLabel(widget.status),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  waitingAtPickup
                                      ? 'El conductor ya está en el punto de recogida.'
                                      : driverPoint == null
                                          ? 'Esperando ubicación del conductor…'
                                          : etaMinutes != null && distanceKm != null
                                              ? '${distanceKm.toStringAsFixed(1)} km · $etaMinutes min aprox.'
                                          : 'Ubicación actualizada en tiempo real.',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (driverPoint != null)
                            const Icon(
                              Icons.gps_fixed_rounded,
                              color: Color(0xFF0B57D0),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'driver_assigned':
        return 'Conductor asignado';
      case 'driver_arriving':
        return 'Conductor en camino';
      case 'driver_waiting':
        return 'Conductor esperando';
      case 'in_progress':
        return 'En viaje';
      case 'completed':
        return 'Completado';
      case 'accepted':
        return 'Repartidor asignado';
      case 'picked_up':
        return 'Recogido';
      case 'in_transit':
        return 'En camino';
      case 'delivered':
        return 'Entregado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return value;
    }
  }
}

class _MapMarker extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool driver;

  const _MapMarker({
    required this.icon,
    required this.label,
    this.driver = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        decoration: BoxDecoration(
          color: driver ? const Color(0xFF0B57D0) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF0B57D0),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: driver ? Colors.white : const Color(0xFF0B57D0),
        ),
      ),
    );
  }
}

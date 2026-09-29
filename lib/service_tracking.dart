import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'core/supabase_client.dart';

class ServiceTrackingPage extends StatelessWidget {
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

  double? _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final pickup = pickupLatitude != null && pickupLongitude != null
        ? LatLng(pickupLatitude!, pickupLongitude!)
        : null;
    final destination =
        destinationLatitude != null && destinationLongitude != null
            ? LatLng(destinationLatitude!, destinationLongitude!)
            : null;

    if (pickup == null && destination == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
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
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Estado: ${_statusLabel(status)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('driver_profiles')
            .stream(primaryKey: ['id'])
            .eq('id', driverId),
        builder: (context, snapshot) {
          final driver = snapshot.data?.isNotEmpty == true
              ? snapshot.data!.first
              : null;
          final driverLat = _number(driver?['latitude']);
          final driverLng = _number(driver?['longitude']);
          final driverPoint = driverLat != null && driverLng != null
              ? LatLng(driverLat, driverLng)
              : null;

          final points = <LatLng>[
            if (pickup != null) pickup,
            if (destination != null) destination,
            if (driverPoint != null) driverPoint,
          ];

          return Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: driverPoint ?? initialCenter,
                  initialZoom: 14,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.express.delivery',
                  ),
                  if (pickup != null && destination != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [pickup, destination],
                          strokeWidth: 4,
                          color: const Color(0xFF0B57D0),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      if (pickup != null)
                        Marker(
                          point: pickup,
                          width: 48,
                          height: 48,
                          child: const _MapMarker(
                            icon: Icons.trip_origin_rounded,
                            label: 'Origen',
                          ),
                        ),
                      if (destination != null)
                        Marker(
                          point: destination,
                          width: 48,
                          height: 48,
                          child: const _MapMarker(
                            icon: Icons.location_on_rounded,
                            label: 'Destino',
                          ),
                        ),
                      if (driverPoint != null)
                        Marker(
                          point: driverPoint,
                          width: 54,
                          height: 54,
                          child: const _MapMarker(
                            icon: Icons.local_taxi_rounded,
                            label: 'Conductor',
                            driver: true,
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
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            driverPoint == null
                                ? Icons.location_searching_rounded
                                : Icons.gps_fixed_rounded,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              driverPoint == null
                                  ? 'Esperando ubicación del conductor…'
                                  : 'Ubicación del conductor actualizada en tiempo real.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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

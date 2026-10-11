import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'core/supabase_client.dart';
import 'express_branding.dart';
import 'map_provider.dart';

class PublicTripSharePage extends StatefulWidget {
  final String token;

  const PublicTripSharePage({
    super.key,
    required this.token,
  });

  @override
  State<PublicTripSharePage> createState() => _PublicTripSharePageState();
}

class _PublicTripSharePageState extends State<PublicTripSharePage>
    with WidgetsBindingObserver {
  Timer? _timer;
  Map<String, dynamic>? _state;
  Object? _error;
  bool _loading = true;
  bool _activeInForeground = true;
  int _requestRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_activeInForeground) {
        _refresh(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _activeInForeground = state == AppLifecycleState.resumed;
    if (_activeInForeground) {
      _refresh(silent: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    final revision = ++_requestRevision;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final raw = await supabase.rpc(
        'get_shared_trip',
        params: {'p_token': widget.token},
      );
      if (!mounted || revision != _requestRevision) return;
      setState(() {
        _state = raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{'ok': false, 'active': false};
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || revision != _requestRevision) return;
      if (!silent || _state == null) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'driver_assigned':
        return 'Conductor asignado';
      case 'driver_arriving':
        return 'El conductor va hacia el punto de recogida';
      case 'driver_waiting':
        return 'El conductor llegó al punto de recogida';
      case 'in_progress':
        return 'Viaje en curso';
      case 'emergency':
        return 'Alerta de emergencia activa';
      default:
        return 'Viaje Express';
    }
  }

  static String _locationFreshness(Object? raw) {
    final updated = DateTime.tryParse(raw?.toString() ?? '')?.toUtc();
    if (updated == null) return 'Ubicación del conductor aún no disponible';

    final age = DateTime.now().toUtc().difference(updated);
    if (age.isNegative || age.inSeconds < 15) {
      return 'Ubicación actualizada hace unos segundos';
    }
    if (age.inMinutes < 1) {
      return 'Ubicación actualizada hace ' + age.inSeconds.toString() + ' s';
    }
    if (age.inHours < 1) {
      return 'Ubicación actualizada hace ' + age.inMinutes.toString() + ' min';
    }
    return 'Última ubicación disponible hace ' + age.inHours.toString() + ' h';
  }

  Widget _ended(String reason) {
    final expired = reason == 'expired';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ExpressOfficialLogo(size: 64, radius: 18),
                      const SizedBox(height: 18),
                      Icon(
                        expired
                            ? Icons.link_off_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 52,
                        color: const Color(0xFF667085),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        expired
                            ? 'Este enlace ya venció'
                            : 'Este viaje ya terminó',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Por seguridad, Express deja de compartir la ubicación cuando el viaje finaliza, se cancela o vence el enlace.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF667085),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _invalid() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ExpressOfficialLogo(size: 64, radius: 18),
                      const SizedBox(height: 18),
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 52,
                        color: Color(0xFF667085),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Enlace no disponible',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'El enlace no es válido o ya fue desactivado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _state == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _state == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 52),
                  const SizedBox(height: 14),
                  const Text(
                    'No pudimos actualizar el viaje',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final data = _state ?? const <String, dynamic>{};
    if (data['ok'] != true) return _invalid();
    if (data['active'] != true) {
      return _ended(data['reason']?.toString() ?? 'ended');
    }

    final status = data['status']?.toString() ?? '';
    final driver = data['driver_name']?.toString().trim();
    final vehicle = _map(data['vehicle']);
    final driverLocation = _map(data['driver_location']);
    final pickup = _map(data['pickup']);
    final destination = _map(data['destination']);

    final driverLat = _asDouble(driverLocation['latitude']);
    final driverLng = _asDouble(driverLocation['longitude']);
    final pickupLat = _asDouble(pickup['latitude']);
    final pickupLng = _asDouble(pickup['longitude']);
    final destinationLat = _asDouble(destination['latitude']);
    final destinationLng = _asDouble(destination['longitude']);

    final mapCenter = driverLat != null && driverLng != null
        ? LatLng(driverLat, driverLng)
        : pickupLat != null && pickupLng != null
            ? LatLng(pickupLat, pickupLng)
            : destinationLat != null && destinationLng != null
                ? LatLng(destinationLat, destinationLng)
                : null;

    final vehicleParts = [
      vehicle['color']?.toString().trim(),
      vehicle['brand']?.toString().trim(),
      vehicle['model']?.toString().trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).toList();
    final plate = vehicle['plate']?.toString().trim();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExpressOfficialLogo(size: 32, radius: 9),
            SizedBox(width: 10),
            Text('Seguimiento compartido'),
          ],
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusLabel(status),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      driver?.isNotEmpty == true
                          ? 'Conductor: ' + driver!
                          : 'Conductor Express',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (vehicleParts.isNotEmpty || plate?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (vehicleParts.isNotEmpty) vehicleParts.join(' '),
                          if (plate?.isNotEmpty == true) 'Patente ' + plate!,
                        ].join(' · '),
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.my_location_rounded,
                          size: 18,
                          color: Color(0xFF0B57D0),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _locationFreshness(driverLocation['updated_at']),
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (mapCenter != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 330,
                  child: FlutterMap(
                    key: ValueKey(
                      'shared-trip-' +
                          (driverLat ?? mapCenter.latitude).toStringAsFixed(5) +
                          '-' +
                          (driverLng ?? mapCenter.longitude).toStringAsFixed(5),
                    ),
                    options: MapOptions(
                      initialCenter: mapCenter,
                      initialZoom: 14.5,
                    ),
                    children: [
                      const ExpressBaseTileLayer(),
                      MarkerLayer(
                        markers: [
                          if (driverLat != null && driverLng != null)
                            Marker(
                              point: LatLng(driverLat, driverLng),
                              width: 52,
                              height: 52,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0B57D0),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      blurRadius: 10,
                                      color: Color(0x33000000),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.directions_car_filled_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (status != 'in_progress' &&
                              pickupLat != null &&
                              pickupLng != null)
                            Marker(
                              point: LatLng(pickupLat, pickupLng),
                              width: 42,
                              height: 42,
                              child: const Icon(
                                Icons.trip_origin_rounded,
                                color: Color(0xFF16A34A),
                                size: 36,
                              ),
                            ),
                          if ((status == 'in_progress' || status == 'emergency') &&
                              destinationLat != null &&
                              destinationLng != null)
                            Marker(
                              point: LatLng(destinationLat, destinationLng),
                              width: 42,
                              height: 42,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFFD92D20),
                                size: 40,
                              ),
                            ),
                        ],
                      ),
                      const ExpressMapAttribution(),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _RouteCard(
              icon: Icons.trip_origin_rounded,
              label: 'Origen',
              value: pickup['address']?.toString() ?? 'Origen del viaje',
            ),
            const SizedBox(height: 8),
            _RouteCard(
              icon: Icons.location_on_rounded,
              label: 'Destino',
              value:
                  destination['address']?.toString() ?? 'Destino del viaje',
            ),
            const SizedBox(height: 18),
            const Text(
              'Este enlace es seguro y temporal. No muestra teléfonos, datos de pago ni información privada del pasajero. Se desactiva cuando el viaje termina, se cancela o vence.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RouteCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0B57D0)),
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF667085),
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

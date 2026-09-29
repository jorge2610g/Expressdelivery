import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'location_service.dart';

class PickedLocation {
  final String label;
  final double latitude;
  final double longitude;

  const PickedLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
  });
}

class LocationPickerPage extends StatefulWidget {
  final String title;
  final String? initialLabel;
  final double? initialLatitude;
  final double? initialLongitude;

  const LocationPickerPage({
    super.key,
    required this.title,
    this.initialLabel,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final mapController = MapController();
  final locationService = const ExpressLocationService();
  late final TextEditingController labelController;

  LatLng? selected;
  bool locating = false;
  String? error;

  @override
  void initState() {
    super.initState();
    labelController = TextEditingController(text: widget.initialLabel ?? '');
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      selected = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _useCurrentLocation(silent: true),
      );
    }
  }

  Future<void> _useCurrentLocation({bool silent = false}) async {
    if (locating) return;
    setState(() {
      locating = true;
      if (!silent) error = null;
    });

    try {
      final position = await locationService.currentPosition();
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        selected = point;
        if (labelController.text.trim().isEmpty) {
          labelController.text = 'Mi ubicación actual';
        }
        error = null;
      });
      mapController.move(point, 16);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void _confirm() {
    final point = selected;
    if (point == null) {
      setState(() => error = 'Selecciona un punto en el mapa.');
      return;
    }

    final label = labelController.text.trim().isEmpty
        ? 'Ubicación seleccionada'
        : labelController.text.trim();

    Navigator.pop(
      context,
      PickedLocation(
        label: label,
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    );
  }

  @override
  void dispose() {
    labelController.dispose();
    mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = selected ?? const LatLng(-14.8333, -64.9000);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: selected == null ? 12 : 16,
                    onTap: (_, point) {
                      setState(() {
                        selected = point;
                        error = null;
                        if (labelController.text.trim().isEmpty) {
                          labelController.text = 'Ubicación seleccionada';
                        }
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.express.delivery',
                    ),
                    if (selected != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: selected!,
                            width: 52,
                            height: 52,
                            child: const Icon(
                              Icons.location_on_rounded,
                              size: 46,
                              color: Color(0xFF0B57D0),
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
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton.small(
                    heroTag: 'current-location',
                    onPressed:
                        locating ? null : () => _useCurrentLocation(),
                    child: locating
                        ? const SizedBox.square(
                            dimension: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                  ),
                ),
              ],
            ),
          ),
          Material(
            elevation: 8,
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre o dirección',
                        hintText: 'Ej. Av. Principal 123',
                        prefixIcon:
                            Icon(Icons.edit_location_alt_outlined),
                      ),
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${selected!.latitude.toStringAsFixed(6)}, ${selected!.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _confirm,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Usar esta ubicación'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

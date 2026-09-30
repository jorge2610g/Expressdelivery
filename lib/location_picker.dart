import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

class _PlaceSuggestion {
  final String label;
  final double latitude;
  final double longitude;

  const _PlaceSuggestion({
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
  final double? forbiddenLatitude;
  final double? forbiddenLongitude;
  final String forbiddenMessage;

  const LocationPickerPage({
    super.key,
    required this.title,
    this.initialLabel,
    this.initialLatitude,
    this.initialLongitude,
    this.forbiddenLatitude,
    this.forbiddenLongitude,
    this.forbiddenMessage =
        'No puedes usar la misma ubicación. Selecciona otro punto.',
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final mapController = MapController();
  final locationService = const ExpressLocationService();
  late final TextEditingController labelController;
  final searchController = TextEditingController();

  LatLng? selected;
  bool locating = false;
  bool searching = false;
  bool reverseGeocoding = false;
  bool draggingPin = false;
  bool mapMoving = false;
  String? error;
  LatLng? dragOrigin;
  LatLng? centerHint;

  Timer? searchDebounce;
  Timer? mapSettleDebounce;
  int searchSerial = 0;
  int reverseSerial = 0;
  List<_PlaceSuggestion> suggestions = const [];

  @override
  void initState() {
    super.initState();
    labelController = TextEditingController(text: widget.initialLabel ?? '');
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      selected = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      centerHint = selected;
    } else if (widget.forbiddenLatitude != null &&
        widget.forbiddenLongitude != null) {
      // El destino comienza visualmente en la ubicación de origen/actual.
      // La validación de "mismo origen y destino" ocurre únicamente
      // cuando el usuario confirma con "Usar esta ubicación".
      selected = LatLng(
        widget.forbiddenLatitude!,
        widget.forbiddenLongitude!,
      );
      centerHint = selected;
      if (labelController.text.trim().isEmpty) {
        labelController.text = 'Mi ubicación actual';
      }
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
        centerHint = point;
        labelController.text = 'Mi ubicación actual';
        suggestions = const [];
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

  bool _isForbidden(LatLng point) {
    final lat = widget.forbiddenLatitude;
    final lng = widget.forbiddenLongitude;
    if (lat == null || lng == null) return false;

    final meters = const Distance().as(
      LengthUnit.Meter,
      LatLng(lat, lng),
      point,
    );
    return meters < 25;
  }

  void _showForbiddenError() {
    if (!mounted) return;
    setState(() {
      error = widget.forbiddenMessage;
      suggestions = const [];
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(widget.forbiddenMessage)),
      );
  }

  void _queueSuggestions(String value) {
    searchDebounce?.cancel();
    final query = value.trim();

    if (query.length < 3) {
      if (suggestions.isNotEmpty) {
        setState(() => suggestions = const []);
      }
      return;
    }

    searchDebounce = Timer(const Duration(milliseconds: 420), () {
      _loadSuggestions(query);
    });
  }

  Future<List<_PlaceSuggestion>> _fetchSuggestions(String query) async {
    final bias = selected;
    final params = <String, String>{
      'q': query,
      'format': 'jsonv2',
      'limit': '6',
      'addressdetails': '1',
      'dedupe': '1',
    };

    if (bias != null) {
      final left = bias.longitude - 0.35;
      final top = bias.latitude + 0.35;
      final right = bias.longitude + 0.35;
      final bottom = bias.latitude - 0.35;
      params['viewbox'] = [
        left.toStringAsFixed(6),
        top.toStringAsFixed(6),
        right.toStringAsFixed(6),
        bottom.toStringAsFixed(6),
      ].join(',');
      params['bounded'] = '0';
    }

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      params,
    );

    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Accept-Language': 'es',
      },
    );

    if (response.statusCode != 200) {
      throw StateError('No se pudo buscar la dirección.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    final results = <_PlaceSuggestion>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final latitude = double.tryParse(row['lat']?.toString() ?? '');
      final longitude = double.tryParse(row['lon']?.toString() ?? '');
      final label = row['display_name']?.toString().trim();
      if (latitude == null ||
          longitude == null ||
          label == null ||
          label.isEmpty) {
        continue;
      }
      results.add(
        _PlaceSuggestion(
          label: label,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }
    return results;
  }

  Future<void> _loadSuggestions(String query) async {
    final requestId = ++searchSerial;
    if (mounted) {
      setState(() {
        searching = true;
        error = null;
      });
    }

    try {
      final results = await _fetchSuggestions(query);
      if (!mounted || requestId != searchSerial) return;
      setState(() {
        suggestions = results;
        if (results.isEmpty) {
          error = 'No encontramos coincidencias para esa búsqueda.';
        }
      });
    } catch (e) {
      if (!mounted || requestId != searchSerial) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted && requestId == searchSerial) {
        setState(() => searching = false);
      }
    }
  }

  Future<void> _searchAddress() async {
    final query = searchController.text.trim();
    if (query.isEmpty || searching) return;

    FocusScope.of(context).unfocus();
    setState(() {
      searching = true;
      error = null;
    });

    try {
      final results = await _fetchSuggestions(query);
      if (!mounted) return;

      if (results.isEmpty) {
        setState(() {
          suggestions = const [];
          error = 'No encontramos esa dirección.';
        });
        return;
      }

      _selectSuggestion(results.first);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void _selectSuggestion(_PlaceSuggestion place) {
    final point = LatLng(place.latitude, place.longitude);
    setState(() {
      selected = point;
      labelController.text = place.label;
      searchController.text = place.label;
      searchController.selection = TextSelection.collapsed(
        offset: searchController.text.length,
      );
      suggestions = const [];
      error = null;
    });
    mapController.move(point, 17);
    FocusScope.of(context).unfocus();
  }

  Future<void> _reverseGeocode(LatLng point) async {
    final requestSerial = ++reverseSerial;
    if (mounted) {
      setState(() {
        reverseGeocoding = true;
        error = null;
      });
    }

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
          'Accept': 'application/json',
          'Accept-Language': 'es',
        },
      );

      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;
      final row = Map<String, dynamic>.from(decoded);
      final label = row['display_name']?.toString().trim();
      if (!mounted ||
          requestSerial != reverseSerial ||
          label == null ||
          label.isEmpty) {
        return;
      }

      setState(() {
        labelController.text = label;
        error = null;
      });
    } catch (_) {
      // Mantener coordenadas seleccionadas aunque reverse geocoding no responda.
    } finally {
      if (mounted && requestSerial == reverseSerial) {
        setState(() => reverseGeocoding = false);
      }
    }
  }

  void _onMapPositionChanged(MapCamera camera) {
    selected = camera.center;
    mapSettleDebounce?.cancel();

    if (!mapMoving) {
      reverseSerial++;
      setState(() {
        mapMoving = true;
        reverseGeocoding = false;
        labelController.text = 'Buscando dirección…';
        suggestions = const [];
        error = null;
      });
    }

    mapSettleDebounce = Timer(
      const Duration(milliseconds: 420),
      _finishMapMovement,
    );
  }

  void _finishMapMovement() {
    if (!mounted) return;

    LatLng point;
    try {
      point = mapController.camera.center;
    } catch (_) {
      final current = selected;
      if (current == null) return;
      point = current;
    }

    setState(() {
      selected = point;
      mapMoving = false;
      labelController.text = 'Buscando dirección…';
    });

    _reverseGeocode(point);
  }


  Offset? _selectedScreenOffset() {
    final point = selected;
    if (point == null) return null;
    try {
      return mapController.camera.latLngToScreenOffset(point);
    } catch (_) {
      return null;
    }
  }

  void _cancelPinDrag() {
    if (!mounted) return;
    setState(() {
      draggingPin = false;
      dragOrigin = null;
    });
  }

  LatLng _movePointByPixels(LatLng point, Offset delta) {
    double zoom = 16;
    try {
      zoom = mapController.camera.zoom;
    } catch (_) {}

    final worldSize = 256.0 * math.pow(2.0, zoom).toDouble();
    final x = (point.longitude + 180.0) / 360.0 * worldSize;
    final latRad = point.latitude * math.pi / 180.0;
    final sinLat = math.sin(latRad).clamp(-0.9999, 0.9999).toDouble();
    final y =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
            worldSize;

    final nextX = x + delta.dx;
    final nextY = y + delta.dy;

    final longitude = nextX / worldSize * 360.0 - 180.0;
    final n = math.pi - (2.0 * math.pi * nextY / worldSize);
    final latitude =
        math.atan((math.exp(n) - math.exp(-n)) / 2.0) * 180.0 / math.pi;

    return LatLng(
      latitude.clamp(-85.0511, 85.0511).toDouble(),
      (((longitude + 540.0) % 360.0) - 180.0),
    );
  }

  void _dragPinStart(DragStartDetails details) {
    if (selected == null) return;
    setState(() {
      dragOrigin = selected;
      draggingPin = true;
      suggestions = const [];
      error = null;
    });
  }

  void _dragPinUpdate(DragUpdateDetails details) {
    final point = selected;
    if (point == null) return;
    setState(() {
      selected = _movePointByPixels(point, details.delta);
      labelController.text = 'Ajustando ubicación…';
    });
  }

  void _dragPinEnd(DragEndDetails details) {
    final point = selected;
    if (mounted) {
      setState(() {
        draggingPin = false;
        dragOrigin = null;
      });
    }
    if (point != null) _reverseGeocode(point);
  }

  void _selectMapPoint(LatLng point) {
    setState(() {
      selected = point;
      labelController.text = 'Buscando dirección…';
      suggestions = const [];
      error = null;
    });

    double zoom = 16;
    try {
      zoom = mapController.camera.zoom;
    } catch (_) {}
    mapController.move(point, zoom);
  }

  void _confirm() {
    final point = selected;
    if (point == null) {
      setState(() => error = 'Selecciona un punto en el mapa.');
      return;
    }

    if (_isForbidden(point)) {
      _showForbiddenError();
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
    searchDebounce?.cancel();
    mapSettleDebounce?.cancel();
    labelController.dispose();
    searchController.dispose();
    mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter =
        selected ?? centerHint ?? const LatLng(-14.8333, -64.9000);
    final darkMap =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final surface = darkMap ? const Color(0xFF121212) : Colors.white;
    final softSurface =
        darkMap ? const Color(0xFF1D1D1D) : const Color(0xFFF8FAFC);
    final textColor = darkMap ? Colors.white : const Color(0xFF101828);
    final mutedColor =
        darkMap ? const Color(0xFF9CA3AF) : const Color(0xFF667085);
    final borderColor =
        darkMap ? const Color(0xFF333333) : const Color(0xFFD9E0EA);

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: surface,
        foregroundColor: textColor,
        surfaceTintColor: surface,
      ),
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
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                    onTap: (_, point) => _selectMapPoint(point),
                    onPositionChanged: (camera, _) =>
                        _onMapPositionChanged(camera),
                  ),
                  children: [
                    if (darkMap)
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
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                if (selected != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.translate(
                            offset: const Offset(0, 3),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: mapMoving ? 11 : 18,
                              height: mapMoving ? 3 : 6,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(
                                  alpha: mapMoving ? .18 : .30,
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -31),
                            child: AnimatedSlide(
                              offset: mapMoving
                                  ? const Offset(0, -.20)
                                  : Offset.zero,
                              duration: Duration(
                                milliseconds: mapMoving ? 140 : 360,
                              ),
                              curve: mapMoving
                                  ? Curves.easeOutCubic
                                  : Curves.bounceOut,
                              child: AnimatedScale(
                                scale: mapMoving ? 1.08 : 1,
                                duration: const Duration(milliseconds: 150),
                                curve: Curves.easeOutCubic,
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  size: 64,
                                  color: Color(0xFF0B57D0),
                                  shadows: [
                                    Shadow(
                                      color: Color(0x44000000),
                                      blurRadius: 8,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: 14,
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        Card(
                          color: softSurface,
                          surfaceTintColor: softSurface,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                Icon(Icons.search_rounded, color: textColor),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: searchController,
                                    textInputAction: TextInputAction.search,
                                    style: TextStyle(color: textColor),
                                    onChanged: _queueSuggestions,
                                    onSubmitted: (_) => _searchAddress(),
                                    decoration: InputDecoration(
                                      hintText: 'Buscar dirección o lugar',
                                      hintStyle: TextStyle(color: mutedColor),
                                      border: InputBorder.none,
                                      filled: false,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Buscar',
                                  onPressed:
                                      searching ? null : _searchAddress,
                                  icon: searching
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          Icons.arrow_forward_rounded,
                                          color: textColor,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (suggestions.isNotEmpty)
                          Card(
                            color: softSurface,
                            surfaceTintColor: softSurface,
                            margin: const EdgeInsets.only(top: 6),
                            clipBehavior: Clip.antiAlias,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 270,
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: suggestions.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final place = suggestions[index];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.location_on_outlined,
                                      color: Color(0xFF0B57D0),
                                    ),
                                    title: Text(
                                      place.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: textColor),
                                    ),
                                    onTap: () => _selectSuggestion(place),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                  ),
                ),
              ],
            ),
          ),
          Material(
            elevation: 8,
            color: surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Nombre o dirección',
                        labelStyle: TextStyle(color: mutedColor),
                        hintText: 'Ej. Av. Principal 123',
                        hintStyle: TextStyle(color: mutedColor),
                        filled: true,
                        fillColor: softSurface,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(
                            color: Color(0xFF0B57D0),
                            width: 1.5,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.edit_location_alt_outlined,
                          color: mutedColor,
                        ),
                        suffixIcon: reverseGeocoding
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          selected!.latitude.toStringAsFixed(6) +
                              ', ' +
                              selected!.longitude.toStringAsFixed(6),
                          style: TextStyle(
                            color: mutedColor,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.pan_tool_alt_outlined,
                            size: 16,
                            color: Color(0xFF0B57D0),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              mapMoving
                                  ? 'El pin queda suspendido mientras mueves el mapa. Suelta para fijar el punto.'
                                  : 'Mueve el mapa debajo del pin azul. Al detenerte, el pin cae sobre el punto exacto y buscamos la dirección.',
                              style: TextStyle(
                                color: mutedColor,
                                fontSize: 10.5,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
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
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selected == null ||
                                mapMoving ||
                                reverseGeocoding
                            ? null
                            : _confirm,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Usar esta ubicación'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
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

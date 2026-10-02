import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'location_service.dart';
import 'location_permission_disclosure.dart';

const Color _expressBlue = Color(0xFF0B57D0);
const Color _expressDarkSurface = Color(0xFF141414);
const Color _expressDarkSoft = Color(0xFF1E1E1E);
const Color _expressDarkBorder = Color(0xFF343434);
const Color _expressMutedDark = Color(0xFFAAB0BA);
const Color _expressMutedLight = Color(0xFF667085);


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
  final searchFocus = FocusNode();

  LatLng? selected;
  bool locating = false;
  bool searching = false;
  bool reverseGeocoding = false;
  bool draggingPin = false;
  bool mapMoving = false;
  bool guidedMoveInProgress = false;
  bool showMoveTutorial = false;
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
    searchFocus.addListener(_handleSearchFocus);
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

  void _handleSearchFocus() {
    if (!searchFocus.hasFocus) return;
    final query = searchController.text.trim();
    if (query.length >= 2) _queueSuggestions(query);
  }

  Future<void> _useCurrentLocation({bool silent = false}) async {
    if (locating) return;

    if (silent) {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    } else {
      final accepted = await confirmExpressLocationUse(
        context,
        continuousDriverTracking: false,
      );
      if (!accepted || !mounted) return;
    }

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
    unawaited(_runMoveTutorial());
  }

  Future<void> _runMoveTutorial() async {
    final origin = selected;
    if (origin == null || guidedMoveInProgress) return;

    double zoom = 16;
    try {
      zoom = mapController.camera.zoom;
    } catch (_) {}

    guidedMoveInProgress = true;
    mapSettleDebounce?.cancel();
    if (mounted) setState(() => showMoveTutorial = true);

    final target = LatLng(
      origin.latitude + .00075,
      origin.longitude + .00105,
    );

    try {
      for (var step = 1; step <= 8; step++) {
        if (!mounted) return;
        final t = step / 8;
        mapController.move(
          LatLng(
            origin.latitude + (target.latitude - origin.latitude) * t,
            origin.longitude + (target.longitude - origin.longitude) * t,
          ),
          zoom,
        );
        await Future<void>.delayed(const Duration(milliseconds: 28));
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      for (var step = 1; step <= 8; step++) {
        if (!mounted) return;
        final t = step / 8;
        mapController.move(
          LatLng(
            target.latitude + (origin.latitude - target.latitude) * t,
            target.longitude + (origin.longitude - target.longitude) * t,
          ),
          zoom,
        );
        await Future<void>.delayed(const Duration(milliseconds: 28));
      }
      mapController.move(origin, zoom);
    } finally {
      guidedMoveInProgress = false;
      if (mounted) {
        setState(() {
          selected = origin;
          showMoveTutorial = false;
        });
      }
    }
  }

  void _queueSuggestions(String value) {
    searchDebounce?.cancel();
    final query = value.trim();

    if (mounted) {
      setState(() {
        if (error != null && query.isNotEmpty) error = null;
      });
    }

    if (query.length < 2) {
      if (suggestions.isNotEmpty) {
        setState(() => suggestions = const []);
      }
      return;
    }

    searchDebounce = Timer(const Duration(milliseconds: 240), () {
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

    setState(() {
      searching = true;
      error = null;
    });

    try {
      final results = await _fetchSuggestions(query);
      if (!mounted) return;

      setState(() {
        suggestions = results;
        if (results.isEmpty) {
          error = 'No encontramos esa dirección.';
        }
      });
      if (results.isNotEmpty) {
        searchFocus.requestFocus();
      }
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
    if (guidedMoveInProgress) return;
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
    searchFocus.removeListener(_handleSearchFocus);
    labelController.dispose();
    searchController.dispose();
    searchFocus.dispose();
    mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter =
        selected ?? centerHint ?? const LatLng(-14.8333, -64.9000);
    final inheritedBrightness = Theme.of(context).brightness;
    final darkMap = inheritedBrightness == Brightness.dark ||
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final surface = darkMap ? const Color(0xFF141414) : Colors.white;
    final softSurface =
        darkMap ? const Color(0xFF202020) : const Color(0xFFF7F9FC);
    final textColor = darkMap ? Colors.white : const Color(0xFF0F172A);
    final mutedColor =
        darkMap ? const Color(0xFFAAB0BA) : const Color(0xFF667085);
    final borderColor =
        darkMap ? const Color(0xFF3B3B3B) : const Color(0xFFE2E7EE);
    final destinationMode =
        widget.title.contains('dónde') || widget.title.contains('destino');
    final bottomTitle =
        destinationMode ? 'Elige el destino' : 'Selecciona el punto';
    final confirmLabel = destinationMode
        ? 'Confirmar el destino'
        : 'Confirmar ubicación';

    void focusSearch() {
      searchController.text = labelController.text;
      searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: searchController.text.length,
      );
      searchFocus.requestFocus();
    }

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: surface,
        foregroundColor: textColor,
        surfaceTintColor: surface,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
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
                TileLayer(
                  key: ValueKey<String>(
                    darkMap ? 'picker-map-dark' : 'picker-map-light',
                  ),
                  urlTemplate: darkMap
                      ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.express.delivery',
                ),
                RichAttributionWidget(
                  attributions: [
                    const TextSourceAttribution('OpenStreetMap contributors'),
                    if (darkMap) const TextSourceAttribution('CARTO'),
                  ],
                ),
              ],
            ),
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
                        width: mapMoving ? 12 : 20,
                        height: mapMoving ? 4 : 7,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: mapMoving ? .16 : .28,
                          ),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -32),
                      child: AnimatedSlide(
                        offset:
                            mapMoving ? const Offset(0, -.18) : Offset.zero,
                        duration: Duration(
                          milliseconds: mapMoving ? 140 : 340,
                        ),
                        curve:
                            mapMoving ? Curves.easeOutCubic : Curves.bounceOut,
                        child: AnimatedScale(
                          scale: mapMoving ? 1.07 : 1,
                          duration: const Duration(milliseconds: 150),
                          child: const Icon(
                            Icons.location_on_rounded,
                            size: 66,
                            color: Color(0xFF0B63E5),
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
            left: 18,
            right: 18,
            top: 14,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Material(
                    elevation: 4,
                    shadowColor: const Color(0x1F000000),
                    borderRadius: BorderRadius.circular(20),
                    color: surface,
                    child: Container(
                      height: 60,
                      padding: const EdgeInsets.fromLTRB(9, 6, 7, 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _expressBlue.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: _expressBlue,
                              size: 23,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              focusNode: searchFocus,
                              controller: searchController,
                              textInputAction: TextInputAction.search,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                              onChanged: _queueSuggestions,
                              onSubmitted: (_) => _searchAddress(),
                              decoration: InputDecoration(
                                hintText: 'Buscar dirección o lugar',
                                hintStyle: TextStyle(
                                  color: mutedColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filled(
                            tooltip: 'Buscar',
                            onPressed: searching ? null : _searchAddress,
                            style: IconButton.styleFrom(
                              backgroundColor: _expressBlue,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  _expressBlue.withValues(alpha: .55),
                              disabledForegroundColor: Colors.white,
                            ),
                            icon: searching
                                ? const SizedBox.square(
                                    dimension: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 22,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (searchFocus.hasFocus &&
                      (suggestions.isNotEmpty || searching))
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: searching && suggestions.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Buscando lugares cercanos…',
                                    style: TextStyle(
                                      color: mutedColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: suggestions.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: borderColor),
                              itemBuilder: (context, index) {
                                final place = suggestions[index];
                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color:
                                          _expressBlue.withValues(alpha: .10),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.location_on_outlined,
                                      color: _expressBlue,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    place.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onTap: () => _selectSuggestion(place),
                                );
                              },
                            ),
                    ),
                ],
              ),
            ),
          ),
          if (showMoveTutorial)
            Positioned(
              top: 96,
              left: 42,
              right: 42,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showMoveTutorial ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: darkMap
                          ? const Color(0xEE202020)
                          : const Color(0xF2FFFFFF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.swipe_rounded,
                          color: _expressBlue,
                          size: 22,
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            'Desliza el mapa para elegir otro punto',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 18,
            bottom: 292,
            child: SafeArea(
              top: false,
              child: FloatingActionButton.small(
                heroTag: 'current-location',
                backgroundColor: surface,
                foregroundColor: _expressBlue,
                elevation: 7,
                onPressed: locating ? null : () => _useCurrentLocation(),
                child: locating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              elevation: 18,
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 30,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: borderColor,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          bottomTitle,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                          decoration: BoxDecoration(
                            color: softSurface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                color: Color(0xFF0B63E5),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  labelController.text.trim().isEmpty
                                      ? 'Buscando dirección…'
                                      : labelController.text.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: focusSearch,
                                style: TextButton.styleFrom(
                                  backgroundColor: darkMap
                                      ? const Color(0xFF253246)
                                      : const Color(0xFFEAF2FF),
                                  foregroundColor:
                                      _expressBlue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Cambiar',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.pan_tool_alt_outlined,
                              size: 19,
                              color: Color(0xFF0B63E5),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                mapMoving
                                    ? 'Ajustando el punto exacto…'
                                    : destinationMode
                                        ? 'Mueve el mapa para ajustar el punto exacto de tu destino.'
                                        : 'Mueve el mapa para ajustar el punto exacto de encuentro.',
                                style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            error!,
                            style: const TextStyle(
                              color: Color(0xFFD92D20),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            onPressed: selected == null ||
                                    mapMoving ||
                                    reverseGeocoding
                                ? null
                                : _confirm,
                            style: FilledButton.styleFrom(
                              backgroundColor: _expressBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              confirmLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PickupConfirmationPage extends StatefulWidget {
  final PickedLocation initial;

  const PickupConfirmationPage({
    super.key,
    required this.initial,
  });

  @override
  State<PickupConfirmationPage> createState() =>
      _PickupConfirmationPageState();
}

class _PickupConfirmationPageState extends State<PickupConfirmationPage> {
  final mapController = MapController();
  late PickedLocation pickup;
  late LatLng pickupAnchor;
  Timer? pickupSettleDebounce;
  bool resolvingPickup = false;
  bool pickupMapMoving = false;
  int pickupReverseSerial = 0;

  @override
  void initState() {
    super.initState();
    pickup = widget.initial;
    pickupAnchor = LatLng(pickup.latitude, pickup.longitude);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolvePickupAddress();
    });
  }

  Future<void> _resolvePickupAddress({
    LatLng? point,
    bool force = false,
  }) async {
    final target = point ?? LatLng(pickup.latitude, pickup.longitude);
    final currentLabel = pickup.label.trim();
    final generic = currentLabel.isEmpty ||
        currentLabel == 'Mi ubicación actual' ||
        currentLabel == 'Ubicación seleccionada' ||
        currentLabel == 'Buscando dirección…';
    if (!force && !generic) return;

    final requestId = ++pickupReverseSerial;
    if (mounted) setState(() => resolvingPickup = true);

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/reverse',
        {
          'lat': target.latitude.toString(),
          'lon': target.longitude.toString(),
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
      final label = decoded['display_name']?.toString().trim();
      if (!mounted ||
          requestId != pickupReverseSerial ||
          label == null ||
          label.isEmpty) {
        return;
      }

      setState(() {
        pickup = PickedLocation(
          label: label,
          latitude: target.latitude,
          longitude: target.longitude,
        );
        pickupMapMoving = false;
      });
    } catch (_) {
      // Se conserva el punto exacto aun si la dirección no puede resolverse.
    } finally {
      if (mounted && requestId == pickupReverseSerial) {
        setState(() {
          resolvingPickup = false;
          pickupMapMoving = false;
        });
      }
    }
  }

  void _onPickupMapPositionChanged(MapCamera camera) {
    final center = camera.center;
    pickupSettleDebounce?.cancel();

    if (!pickupMapMoving) {
      pickupReverseSerial++;
      setState(() {
        pickupMapMoving = true;
        resolvingPickup = false;
        pickup = PickedLocation(
          label: 'Punto seleccionado',
          latitude: center.latitude,
          longitude: center.longitude,
        );
      });
    } else {
      pickup = PickedLocation(
        label: pickup.label == 'Buscando dirección…'
            ? 'Punto seleccionado'
            : pickup.label,
        latitude: center.latitude,
        longitude: center.longitude,
      );
    }

    pickupSettleDebounce = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      LatLng target;
      try {
        target = mapController.camera.center;
      } catch (_) {
        target = LatLng(pickup.latitude, pickup.longitude);
      }
      setState(() {
        pickup = PickedLocation(
          label: 'Punto seleccionado',
          latitude: target.latitude,
          longitude: target.longitude,
        );
        pickupMapMoving = false;
      });
      _resolvePickupAddress(point: target, force: true);
    });
  }

  @override
  void dispose() {
    pickupSettleDebounce?.cancel();
    mapController.dispose();
    super.dispose();
  }

  Future<void> _changePickup() async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: 'Punto de encuentro',
          initialLabel: pickup.label,
          initialLatitude: pickup.latitude,
          initialLongitude: pickup.longitude,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      pickup = result;
      pickupAnchor = LatLng(result.latitude, result.longitude);
      pickupMapMoving = false;
    });
    mapController.move(pickupAnchor, 17);
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(pickup.latitude, pickup.longitude);
    final dark = Theme.of(context).brightness == Brightness.dark ||
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final surface = dark ? _expressDarkSurface : Colors.white;
    final softSurface =
        dark ? _expressDarkSoft : const Color(0xFFF7F9FC);
    final borderColor =
        dark ? _expressDarkBorder : const Color(0xFFE2E7EE);
    final textColor = dark ? Colors.white : const Color(0xFF101828);
    final muted = dark ? _expressMutedDark : _expressMutedLight;

    return Scaffold(
      backgroundColor: surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: point,
                initialZoom: 17,
                onPositionChanged: (camera, _) =>
                    _onPickupMapPositionChanged(camera),
              ),
              children: [
                TileLayer(
                  key: ValueKey<String>(
                    dark ? 'pickup-map-dark' : 'pickup-map-light',
                  ),
                  urlTemplate: dark
                      ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.express.delivery',
                ),
                RichAttributionWidget(
                  attributions: [
                    const TextSourceAttribution('OpenStreetMap contributors'),
                    if (dark) const TextSourceAttribution('CARTO'),
                  ],
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.translate(
                    offset: const Offset(0, 4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: pickupMapMoving ? 12 : 20,
                      height: pickupMapMoving ? 4 : 7,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha: pickupMapMoving ? .16 : .30,
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -34),
                    child: AnimatedSlide(
                      offset: pickupMapMoving
                          ? const Offset(0, -.14)
                          : Offset.zero,
                      duration: const Duration(milliseconds: 170),
                      curve: Curves.easeOutCubic,
                      child: AnimatedScale(
                        scale: pickupMapMoving ? 1.06 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: const Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 68,
                              color: _expressBlue,
                              shadows: [
                                Shadow(
                                  color: Color(0x44000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            Positioned(
                              top: 18,
                              child: Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
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
            left: 18,
            top: 18,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: surface,
                elevation: 6,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back_rounded, color: textColor),
                ),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -.10),
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 290),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: Text(
                  pickupMapMoving || resolvingPickup
                      ? 'Ajustando punto de encuentro…'
                      : 'Aborda en ' + pickup.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 290,
            child: FloatingActionButton.small(
              heroTag: 'pickup-center',
              backgroundColor: surface,
              foregroundColor: _expressBlue,
              elevation: 7,
              onPressed: () => mapController.move(pickupAnchor, 17),
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 32,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 11, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: dark
                                ? _expressDarkBorder
                                : const Color(0xFFD7DCE3),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 17),
                      Text(
                        'Selecciona un punto de encuentro',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                        decoration: BoxDecoration(
                          color: softSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.my_location_rounded,
                              color: _expressBlue,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                pickupMapMoving || resolvingPickup
                                    ? 'Buscando dirección…'
                                    : pickup.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed:
                                  pickupMapMoving || resolvingPickup
                                      ? null
                                      : _changePickup,
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    dark ? Colors.white : _expressBlue,
                                backgroundColor: dark
                                    ? const Color(0xFF262626)
                                    : const Color(0xFFEAF2FF),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: borderColor),
                                ),
                              ),
                              child: const Text(
                                'Cambiar',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Confirma dónde quieres que el conductor te recoja.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: FilledButton(
                          onPressed: pickupMapMoving || resolvingPickup
                              ? null
                              : () => Navigator.pop(context, pickup),
                          style: FilledButton.styleFrom(
                            backgroundColor: _expressBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Text(
                            'Solicitar',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
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
      ),
    );
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'map_provider.dart';

const _ink = Color(0xFF202432);
const _blue = Color(0xFF536C9D);
const _muted = Color(0xFF697181);
const _line = Color(0xFFE4E6ED);

class RestaurantApplicationPage extends StatefulWidget {
  const RestaurantApplicationPage({super.key, this.previous});

  final Map<String, dynamic>? previous;

  @override
  State<RestaurantApplicationPage> createState() =>
      _RestaurantApplicationPageState();
}

class _RestaurantApplicationPageState extends State<RestaurantApplicationPage> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _map = MapController();
  final _picker = ImagePicker();
  Timer? _addressSearchTimer;
  Timer? _mapAddressTimer;
  LatLng _point = const LatLng(-20.214, -70.153);
  Uint8List? _logoBytes;
  Uint8List? _coverBytes;
  String _logoMime = 'image/jpeg';
  String _coverMime = 'image/jpeg';
  String? _logoUrl;
  String? _coverUrl;
  String? _zoneId;
  String? _countryCode;
  String? _message;
  String? _locationMessage;
  String _mapLocationLabel = 'Ubicación marcada';
  bool _busy = false;
  bool _loading = true;
  bool _success = false;
  List<Map<String, dynamic>> _zones = [];
  List<Map<String, dynamic>> _requirements = [];
  List<({String label, double latitude, double longitude})>
  _addressSuggestions = [];
  bool _searchingAddress = false;
  bool _addressSearchComplete = false;
  bool _selectingAddress = false;
  int _addressSearchRevision = 0;
  bool _resolvingMapAddress = false;
  bool _mapGestureActive = false;
  bool _detectingLocation = false;
  final Map<String, ({Uint8List bytes, String mime})> _documents = {};
  final Map<String, String> _existingDocuments = {};

  List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    final row = widget.previous;
    _name.text = row?['restaurant_name']?.toString() ?? '';
    _address.text = row?['address']?.toString() ?? '';
    if (_address.text.trim().isNotEmpty) {
      _mapLocationLabel = _address.text.trim();
    }
    _address.addListener(_scheduleAddressSearch);
    _logoUrl = row?['logo_url']?.toString();
    _coverUrl = row?['cover_image_url']?.toString();
    _zoneId = row?['zone_id']?.toString();
    _countryCode = row?['country_code']?.toString().toUpperCase();
    for (final document in _rows(row?['requirements'])) {
      final id = document['id']?.toString();
      final path = document['object_path']?.toString();
      if (id != null && path != null && path.isNotEmpty) {
        _existingDocuments[id] = path;
      }
    }
    final lat = double.tryParse(row?['latitude']?.toString() ?? '');
    final lng = double.tryParse(row?['longitude']?.toString() ?? '');
    if (lat != null && lng != null) _point = LatLng(lat, lng);
    _loadZones();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _map.dispose();
    _addressSearchTimer?.cancel();
    _mapAddressTimer?.cancel();
    super.dispose();
  }

  void _scheduleAddressSearch() {
    if (_selectingAddress) return;
    final revision = ++_addressSearchRevision;
    _addressSearchTimer?.cancel();
    final query = _address.text.trim();
    if (_addressSuggestions.isNotEmpty ||
        _searchingAddress ||
        _addressSearchComplete) {
      setState(() {
        _addressSuggestions = [];
        _searchingAddress = false;
        _addressSearchComplete = false;
      });
    }
    if (query.length < 3) {
      if (_addressSuggestions.isNotEmpty || _searchingAddress) {
        setState(() {
          _addressSuggestions = [];
          _searchingAddress = false;
        });
      }
      return;
    }
    _addressSearchTimer = Timer(const Duration(milliseconds: 650), () {
      _searchAddress(query, revision);
    });
  }

  Future<void> _searchAddress(String query, int revision) async {
    final selectedZone = _zones.where((z) => z['id']?.toString() == _zoneId);
    final city = selectedZone.isEmpty
        ? ''
        : selectedZone.first['name']?.toString() ?? '';
    final country = selectedZone.isEmpty
        ? (_countryCode ?? '').toLowerCase()
        : selectedZone.first['country_code']?.toString().toLowerCase() ?? '';
    if (country.length != 2) {
      setState(() {
        _addressSuggestions = [];
        _searchingAddress = false;
        _addressSearchComplete = true;
      });
      return;
    }
    setState(() => _searchingAddress = true);
    try {
      final results = await ExpressMapProvider.searchAddress(
        query: query,
        countryCode: country,
        proximity: _point,
        city: city,
      );
      if (!mounted ||
          revision != _addressSearchRevision ||
          _address.text.trim() != query) {
        return;
      }
      setState(() {
        _addressSuggestions = results;
        _searchingAddress = false;
        _addressSearchComplete = true;
      });
    } catch (_) {
      if (mounted && revision == _addressSearchRevision) {
        setState(() {
          _searchingAddress = false;
          _addressSearchComplete = true;
        });
      }
    }
  }

  void _selectAddress(
    ({String label, double latitude, double longitude}) result,
  ) {
    // Ignore responses from lookups that started before this selection.
    _addressSearchRevision++;
    _addressSearchTimer?.cancel();
    _mapAddressTimer?.cancel();
    _selectingAddress = true;
    _address.text = result.label;
    _mapLocationLabel = result.label;
    _selectingAddress = false;
    final point = LatLng(result.latitude, result.longitude);
    setState(() {
      _point = point;
      _addressSuggestions = [];
      _searchingAddress = false;
      _addressSearchComplete = false;
      _resolvingMapAddress = false;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    _map.move(point, 17);
  }

  Future<void> _fillAddressFromMap(LatLng point) async {
    if (!mounted || _point != point) return;
    final selectedZone = _zones.where((z) => z['id']?.toString() == _zoneId);
    final country = selectedZone.isEmpty
        ? _countryCode
        : selectedZone.first['country_code']?.toString();
    setState(() => _resolvingMapAddress = true);
    try {
      final label = await ExpressMapProvider.reverseGeocodeLocationLabel(
        point: point,
        countryCode: country,
      );
      if (!mounted || _point != point) return;
      _selectingAddress = true;
      _mapLocationLabel = label ?? 'Ubicación marcada';
      if (label != null && label.isNotEmpty) _address.text = label;
      _selectingAddress = false;
    } finally {
      if (mounted && _point == point) {
        setState(() => _resolvingMapAddress = false);
      }
    }
  }

  void _scheduleMapAddressLookup(LatLng point) {
    _mapAddressTimer?.cancel();
    _mapAddressTimer = Timer(const Duration(milliseconds: 650), () {
      _fillAddressFromMap(point);
    });
  }

  void _handleMapEvent(MapEvent event) {
    if (event is MapEventMoveStart &&
        (event.source == MapEventSource.dragStart ||
            event.source == MapEventSource.multiFingerGestureStart)) {
      _mapGestureActive = true;
      _mapAddressTimer?.cancel();
      return;
    }
    final isGestureEnd =
        event is MapEventMoveEnd &&
        (event.source == MapEventSource.dragEnd ||
            event.source == MapEventSource.multiFingerEnd);
    if (isGestureEnd) {
      _mapGestureActive = false;
      final point = event.camera.center;
      _point = point;
      _scheduleMapAddressLookup(point);
    } else if (event is MapEventFlingAnimation) {
      final point = event.camera.center;
      _point = point;
      _scheduleMapAddressLookup(point);
    }
  }

  Future<void> _loadZones() async {
    try {
      final zones = _rows(
        await supabase.rpc(
          'marketplace_restaurant_zones',
          params: {'p_channel': ExpressRuntimeChannel.name},
        ),
      );
      if (!mounted) return;
      final selected = zones.any((z) => z['id']?.toString() == _zoneId)
          ? _zoneId
          : null;
      final selectedZone = zones.where((z) => z['id']?.toString() == selected);
      final countryCode = selectedZone.isNotEmpty
          ? selectedZone.first['country_code']?.toString().toUpperCase()
          : _countryCode;
      setState(() {
        _zones = zones;
        _zoneId = selected;
        _countryCode = countryCode;
        _loading = false;
      });
      await _loadRequirements();
      if (selected != null) {
        _moveToSelectedCity();
      } else {
        await _detectCurrentLocation(requestPermission: false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'No pudimos cargar las ciudades. Intenta nuevamente.';
        });
      }
    }
  }

  Future<void> _loadRequirements() async {
    final zoneId = _zoneId;
    if (zoneId == null) return;
    try {
      final requirements = _rows(
        await supabase.rpc(
          'marketplace_restaurant_requirements',
          params: {
            'p_zone_id': zoneId,
            'p_channel': ExpressRuntimeChannel.name,
          },
        ),
      );
      if (mounted) setState(() => _requirements = requirements);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'No pudimos cargar los requisitos.');
      }
    }
  }

  void _moveToSelectedCity() {
    if (!mounted) return;
    final city = _zones.where((z) => z['id']?.toString() == _zoneId);
    if (city.isEmpty) return;
    final lat = double.tryParse(
      city.first['center_latitude']?.toString() ?? '',
    );
    final lng = double.tryParse(
      city.first['center_longitude']?.toString() ?? '',
    );
    if (lat == null || lng == null) return;
    final point = LatLng(lat, lng);
    setState(() => _point = point);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _map.move(point, 13);
    });
  }

  String? _nearestZoneId(List<Map<String, dynamic>> zones) {
    Map<String, dynamic>? nearest;
    var nearestDistance = double.infinity;
    for (final zone in zones) {
      final lat = double.tryParse(zone['center_latitude']?.toString() ?? '');
      final lng = double.tryParse(zone['center_longitude']?.toString() ?? '');
      if (lat == null || lng == null) continue;
      final distance = const Distance().as(
        LengthUnit.Kilometer,
        _point,
        LatLng(lat, lng),
      );
      if (distance < nearestDistance) {
        nearest = zone;
        nearestDistance = distance;
      }
    }
    if (nearest != null && nearestDistance <= 100) {
      return nearest['id']?.toString();
    }
    return null;
  }

  String _countryName(String code) => switch (code.toUpperCase()) {
    'CL' => 'Chile',
    'BO' => 'Bolivia',
    _ => code.toUpperCase(),
  };

  List<String> get _countryCodes => {
    ..._zones
        .map((zone) => zone['country_code']?.toString().toUpperCase() ?? '')
        .where((code) => code.isNotEmpty),
    if (_countryCode?.trim().length == 2) _countryCode!.toUpperCase(),
  }.toList()..sort();

  List<Map<String, dynamic>> get _countryZones => _zones
      .where(
        (zone) =>
            zone['country_code']?.toString().toUpperCase() == _countryCode,
      )
      .toList();

  Future<void> _changeCountry(String? value) async {
    if (value == null || value == _countryCode) return;
    _addressSearchTimer?.cancel();
    _mapAddressTimer?.cancel();
    final cities = _zones
        .where(
          (zone) => zone['country_code']?.toString().toUpperCase() == value,
        )
        .toList();
    setState(() {
      _countryCode = value;
      _zoneId = null;
      _requirements = [];
      _documents.clear();
      _existingDocuments.clear();
      _addressSuggestions = [];
      _locationMessage = null;
    });
    _selectingAddress = true;
    _address.clear();
    _selectingAddress = false;
    if (cities.isNotEmpty) {
      final lat = double.tryParse(
        cities.first['center_latitude']?.toString() ?? '',
      );
      final lng = double.tryParse(
        cities.first['center_longitude']?.toString() ?? '',
      );
      if (lat != null && lng != null) {
        final point = LatLng(lat, lng);
        setState(() => _point = point);
        _map.move(point, 11);
      }
    }
  }

  Future<void> _detectCurrentLocation({bool requestPermission = true}) async {
    if (_detectingLocation) return;
    setState(() {
      _detectingLocation = true;
      _locationMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Activa la ubicación o selecciona país y ciudad.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('El navegador no autorizó la ubicación.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await _applyDetectedLocation(
        LatLng(position.latitude, position.longitude),
      );
    } catch (_) {
      // If browser GPS is unavailable but the user has already selected a
      // country/city or positioned the map, use that point to identify country.
      final hasManualLocation = _countryCode != null || _zoneId != null;
      final point = _point;
      final country = hasManualLocation
          ? (await ExpressMapProvider.reverseGeocodeCountryCode(point: point) ??
              _countryCode)
          : null;
      if (country != null && mounted) {
        await _applyDetectedLocation(point, countryCode: country);
      } else if (mounted) {
        setState(() {
          _locationMessage =
              'No pudimos leer la ubicación del navegador. Permite el acceso a ubicación o continúa con la selección manual.';
        });
      }
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<void> _applyDetectedLocation(
    LatLng point, {
    String? countryCode,
  }) async {
    _point = point;
    final detectedCountry =
        countryCode ??
        await ExpressMapProvider.reverseGeocodeCountryCode(point: point);
    final nearestAnyZone = _nearestZoneId(_zones);
    final nearestAny = _zones.where(
      (row) => row['id']?.toString() == nearestAnyZone,
    );
    final resolvedCountry = detectedCountry ??
        (nearestAny.isEmpty
            ? _countryCode
            : nearestAny.first['country_code']?.toString().toUpperCase()) ??
        _countryCode;
    final sameCountryZones = resolvedCountry == null
        ? <Map<String, dynamic>>[]
        : _zones
            .where(
              (row) =>
                  row['country_code']?.toString().toUpperCase() ==
                  resolvedCountry.toUpperCase(),
            )
            .toList();
    final zoneId = _nearestZoneId(sameCountryZones);
    if (!mounted) return;
    setState(() {
      _zoneId = zoneId;
      _countryCode = resolvedCountry;
      _requirements = [];
      _documents.clear();
      _existingDocuments.clear();
      _locationMessage = resolvedCountry == null
          ? 'Ubicación detectada, pero no identificamos el país. Selecciónalo manualmente.'
          : zoneId == null
          ? 'País detectado: ${_countryName(resolvedCountry)}. No encontramos una ciudad cercana; selecciónala manualmente.'
          : 'País y ciudad detectados. Confirma la ciudad sugerida.';
    });
    if (zoneId != null) await _loadRequirements();
    if (mounted) _map.move(point, 15);
  }

  Future<void> _changeZone(String? value) async {
    if (value == null || value == _zoneId) return;
    _addressSearchTimer?.cancel();
    _mapAddressTimer?.cancel();
    setState(() {
      _zoneId = value;
      _requirements = [];
      _addressSuggestions = [];
      _searchingAddress = false;
      _documents.clear();
      _existingDocuments.clear();
    });
    _selectingAddress = true;
    _address.clear();
    _selectingAddress = false;
    await _loadRequirements();
    _moveToSelectedCity();
  }

  Future<({Uint8List bytes, String mime})?> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final name = picked.name.toLowerCase();
    final mime =
        picked.mimeType ??
        (name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg');
    if (!const {'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
      _show('Selecciona una imagen JPG, PNG o WebP.');
      return null;
    }
    if (bytes.length > 8 * 1024 * 1024) {
      _show('La imagen debe pesar menos de 8 MB.');
      return null;
    }
    return (bytes: bytes, mime: mime);
  }

  Future<void> _pickBrandImage({required bool logo}) async {
    final image = await _pickImage();
    if (image == null) return;
    setState(() {
      if (logo) {
        _logoBytes = image.bytes;
        _logoMime = image.mime;
      } else {
        _coverBytes = image.bytes;
        _coverMime = image.mime;
      }
    });
  }

  Future<void> _pickRequirement(String id) async {
    final image = await _pickImage();
    if (image != null) setState(() => _documents[id] = image);
  }

  Future<String> _uploadBrand(Uint8List bytes, String kind, String mime) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw StateError('Sesión no disponible.');
    final ext = mime == 'image/png'
        ? 'png'
        : mime == 'image/webp'
        ? 'webp'
        : 'jpg';
    final path =
        '${user.id}/${DateTime.now().microsecondsSinceEpoch}-$kind.$ext';
    await supabase.storage
        .from('marketplace-merchant-applications')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    return supabase.storage
        .from('marketplace-merchant-applications')
        .getPublicUrl(path);
  }

  Future<String> _uploadRequirement(
    String id,
    ({Uint8List bytes, String mime}) file,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw StateError('Sesión no disponible.');
    final ext = file.mime == 'image/png'
        ? 'png'
        : file.mime == 'image/webp'
        ? 'webp'
        : 'jpg';
    final path = '${user.id}/${DateTime.now().microsecondsSinceEpoch}-$id.$ext';
    await supabase.storage
        .from('marketplace-merchant-requirements')
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mime),
        );
    return path;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final user = supabase.auth.currentUser;
    if (user == null || user.email == null) {
      _show('Inicia sesión para continuar.');
      return;
    }
    if (_zoneId == null ||
        _name.text.trim().length < 2 ||
        _address.text.trim().length < 4) {
      _show('Completa la ciudad, el nombre y la dirección.');
      return;
    }
    if (_logoBytes == null && (_logoUrl?.isEmpty ?? true)) {
      _show('Agrega el logo del restaurante.');
      return;
    }
    if (_coverBytes == null && (_coverUrl?.isEmpty ?? true)) {
      _show('Agrega una foto de portada.');
      return;
    }
    final missing = _requirements
        .where(
          (r) =>
              r['required'] != false &&
              !_documents.containsKey(r['id']?.toString()) &&
              !_existingDocuments.containsKey(r['id']?.toString()),
        )
        .toList();
    if (missing.isNotEmpty) {
      _show('Completa los documentos obligatorios de $_cityName.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_logoBytes != null) {
        _logoUrl = await _uploadBrand(_logoBytes!, 'logo', _logoMime);
      }
      if (_coverBytes != null) {
        _coverUrl = await _uploadBrand(_coverBytes!, 'cover', _coverMime);
      }
      final docs = <Map<String, String>>[
        for (final entry in _existingDocuments.entries)
          {'requirement_id': entry.key, 'object_path': entry.value},
      ];
      for (final entry in _documents.entries) {
        docs.removeWhere((item) => item['requirement_id'] == entry.key);
        docs.add({
          'requirement_id': entry.key,
          'object_path': await _uploadRequirement(entry.key, entry.value),
        });
      }
      await supabase.rpc(
        'marketplace_submit_merchant_application_v2',
        params: {
          'p_channel': ExpressRuntimeChannel.name,
          'p_email': user.email,
          'p_restaurant_name': _name.text.trim(),
          'p_logo_url': _logoUrl,
          'p_cover_image_url': _coverUrl,
          'p_address': _address.text.trim(),
          'p_latitude': _point.latitude,
          'p_longitude': _point.longitude,
          'p_zone_id': _zoneId,
          'p_requirement_documents': docs,
        },
      );
      if (mounted) {
        setState(() {
          _success = true;
          _message =
              'Recibimos los datos de tu restaurante. Te avisaremos cuando los revisemos.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'No se pudo enviar. Revisa los datos e inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _cityName {
    for (final zone in _zones) {
      if (zone['id']?.toString() == _zoneId) {
        return zone['name']?.toString() ?? 'la ciudad';
      }
    }
    return 'la ciudad';
  }

  int get _completedRequired => _requirements.where((row) {
    final id = row['id']?.toString();
    return row['required'] != false &&
        id != null &&
        (_documents.containsKey(id) || _existingDocuments.containsKey(id));
  }).length;

  void _show(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    if (_success) return _statusPage();
    return Theme(
      data: ThemeData.light(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        colorScheme: ColorScheme.fromSeed(seedColor: _blue),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F7FB),
          foregroundColor: _ink,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Datos del restaurante',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                    children: [
                      const Text(
                        'Completa los pasos para enviar tu solicitud.',
                        style: TextStyle(color: _muted, fontSize: 15),
                      ),
                      const SizedBox(height: 16),
                      _stepCard(
                        number: '1',
                        title: 'Ciudad y ubicación',
                        subtitle: _zoneId == null
                            ? 'Selecciona la ciudad del local.'
                            : '$_cityName · Marca el punto en el mapa.',
                        icon: Icons.location_on_outlined,
                        child: _locationStep(),
                      ),
                      _stepCard(
                        number: '2',
                        title: 'Datos del restaurante',
                        subtitle: 'Agrega el nombre, logo y foto de portada.',
                        icon: Icons.storefront_outlined,
                        child: _restaurantStep(user?.email ?? ''),
                      ),
                      _stepCard(
                        number: '3',
                        title: 'Requisitos de $_cityName',
                        subtitle: _requirements.isEmpty
                            ? 'No hay documentos adicionales para esta ciudad.'
                            : '$_completedRequired de ${_requirements.where((row) => row['required'] != false).length} requisitos obligatorios listos.',
                        icon: Icons.description_outlined,
                        child: _requirementsStep(),
                      ),
                      if (widget.previous?['review_note'] != null) ...[
                        const SizedBox(height: 12),
                        _card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.info_outline,
                              color: _blue,
                            ),
                            title: const Text('Revisa esta observación'),
                            subtitle: Text(
                              widget.previous!['review_note'].toString(),
                            ),
                          ),
                        ),
                      ],
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            _message!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _muted),
                          ),
                        ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(_busy ? 'Enviando…' : 'Enviar solicitud'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _locationStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        initialValue: _countryCodes.contains(_countryCode)
            ? _countryCode
            : null,
        decoration: const InputDecoration(
          labelText: 'País del restaurante',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.public_outlined),
        ),
        items: _countryCodes
            .map(
              (code) => DropdownMenuItem(
                value: code,
                child: Text(_countryName(code)),
              ),
            )
            .toList(),
        onChanged: _busy ? null : _changeCountry,
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue:
            _countryZones.any((zone) => zone['id']?.toString() == _zoneId)
            ? _zoneId
            : null,
        decoration: const InputDecoration(
          labelText: 'Ciudad del restaurante',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.location_city_outlined),
        ),
        items: _countryZones
            .map(
              (zone) => DropdownMenuItem(
                value: zone['id']?.toString(),
                child: Text(zone['name']?.toString() ?? ''),
              ),
            )
            .toList(),
        onChanged: _busy || _countryCode == null ? null : _changeZone,
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy || _detectingLocation
            ? null
            : () => _detectCurrentLocation(),
        icon: _detectingLocation
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location_rounded),
        label: Text(
          _detectingLocation
              ? 'Detectando ubicación…'
              : 'Detectar país y ciudad',
        ),
      ),
      if (_locationMessage != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_locationMessage!, style: const TextStyle(color: _muted)),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _address,
        decoration: InputDecoration(
          labelText: 'Dirección del local',
          hintText: 'Escribe para buscar y seleccionar la dirección',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.edit_location_alt_outlined),
          suffixIcon: _searchingAddress
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
      ),
      if (_addressSuggestions.isNotEmpty)
        Card(
          margin: const EdgeInsets.only(top: 6),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final suggestion in _addressSuggestions)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(
                    suggestion.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _selectAddress(suggestion),
                ),
            ],
          ),
        ),
      if (_addressSearchComplete &&
          _addressSuggestions.isEmpty &&
          _address.text.trim().length >= 3)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _countryCode == null
                ? 'Selecciona primero el país del restaurante para buscar la dirección.'
                : 'No encontramos coincidencias. Prueba con calle, número y ciudad, o marca el lugar en el mapa.',
            style: const TextStyle(color: _muted),
          ),
        ),
      const SizedBox(height: 8),
      const Text(
        'Mueve el mapa hasta que el centro del marcador quede sobre el local.',
        style: TextStyle(color: _muted),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 340,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _point,
                  initialZoom: 15,
                  onMapEvent: _handleMapEvent,
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture && camera.center != _point) {
                      setState(() => _point = camera.center);
                      if (!_mapGestureActive) {
                        _scheduleMapAddressLookup(camera.center);
                      }
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'online.expressviajes',
                  ),
                ],
              ),
              const IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 52),
                  child: Icon(
                    Icons.location_pin,
                    size: 52,
                    color: Colors.red,
                    shadows: [Shadow(color: Colors.white, blurRadius: 4)],
                  ),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    child: Text('Arrastra el mapa para ajustar'),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      if (_resolvingMapAddress)
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Buscando la dirección del punto marcado…'),
            ],
          ),
        ),
      Text(
        _mapLocationLabel,
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
    ],
  );

  Widget _restaurantStep(String email) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(
          labelText: 'Nombre del restaurante',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.storefront_outlined),
        ),
      ),
      const SizedBox(height: 12),
      InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Correo de acceso',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.email_outlined),
        ),
        child: Align(alignment: Alignment.centerLeft, child: Text(email)),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [_imagePicker(logo: true), _imagePicker(logo: false)],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          if (_logoBytes != null) _preview(_logoBytes!, 70, 70),
          if (_logoBytes != null) const SizedBox(width: 10),
          if (_coverBytes != null)
            Expanded(child: _preview(_coverBytes!, double.infinity, 70)),
        ],
      ),
    ],
  );

  Widget _imagePicker({required bool logo}) {
    final bytes = logo ? _logoBytes : _coverBytes;
    final url = logo ? _logoUrl : _coverUrl;
    final label = logo ? 'Logo' : 'Foto de portada';
    return OutlinedButton.icon(
      onPressed: _busy ? null : () => _pickBrandImage(logo: logo),
      icon: Icon(logo ? Icons.storefront_outlined : Icons.image_outlined),
      label: Text(
        bytes != null || (url?.isNotEmpty ?? false)
            ? '$label · listo'
            : 'Agregar $label',
      ),
    );
  }

  Widget _requirementsStep() {
    if (_requirements.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'No se requieren documentos adicionales para esta ciudad.',
          style: TextStyle(color: _muted),
        ),
      );
    }
    return Column(
      children: [
        for (final row in _requirements) ...[
          if (_requirements.first != row)
            const Divider(height: 20, color: _line),
          Builder(
            builder: (_) {
              final id = row['id']?.toString() ?? '';
              final selected = _documents[id];
              final previouslyUploaded = _existingDocuments.containsKey(id);
              final required = row['required'] != false;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    backgroundColor: selected == null && !previouslyUploaded
                        ? const Color(0xFFFFF0E6)
                        : const Color(0xFFE7F5EC),
                    child: Icon(
                      selected == null && !previouslyUploaded
                          ? Icons.description_outlined
                          : Icons.check_rounded,
                      color: selected == null
                          ? const Color(0xFFC45E28)
                          : const Color(0xFF278452),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['label']?.toString() ?? 'Documento',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        if ((row['description'] ?? '').toString().isNotEmpty)
                          Text(
                            row['description'].toString(),
                            style: const TextStyle(color: _muted, fontSize: 13),
                          ),
                        Text(
                          selected != null || previouslyUploaded
                              ? 'Listo para enviar'
                              : required
                              ? 'Falta cargar'
                              : 'Opcional',
                          style: TextStyle(
                            color: selected != null || previouslyUploaded
                                ? const Color(0xFF278452)
                                : const Color(0xFFC45E28),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _pickRequirement(id),
                    child: Text(
                      selected == null && !previouslyUploaded
                          ? 'Subir'
                          : 'Cambiar',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _preview(Uint8List bytes, double width, double height) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.memory(bytes, width: width, height: height, fit: BoxFit.cover),
  );

  Widget _stepCard({
    required String number,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFE8EDF8),
                child: Icon(icon, color: _blue),
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
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: _line),
          child,
        ],
      ),
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0B202432),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );

  Widget _statusPage() => Scaffold(
    backgroundColor: const Color(0xFFF6F7FB),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: _card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 48, color: _blue),
              const SizedBox(height: 12),
              const Text(
                'Solicitud enviada',
                style: TextStyle(
                  fontSize: 22,
                  color: _ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _message ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

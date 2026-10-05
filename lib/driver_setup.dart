import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'services/express_service.dart';

class DriverSetupPage extends StatefulWidget {
  final ExpressService service;
  const DriverSetupPage({super.key, required this.service});

  @override
  State<DriverSetupPage> createState() => _DriverSetupPageState();
}

class _DriverSetupPageState extends State<DriverSetupPage> with WidgetsBindingObserver {
  final brand = TextEditingController();
  final model = TextEditingController();
  final color = TextEditingController();
  final plate = TextEditingController();
  final year = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final Map<String, _DocumentDraft> _documents = <String, _DocumentDraft>{};

  int step = 0;
  bool loading = true;
  bool saving = false;
  bool detecting = false;
  bool diditBusy = false;
  String approval = 'pending';
  Map<String, dynamic> diditVerification = <String, dynamic>{};
  String? diditError;

  String? countryCode;
  String? zoneId;
  String? profilePhotoPath;
  final List<String> vehiclePhotoPaths = <String>[];
  final Set<String> selectedServices = <String>{};
  String vehicleType = 'motorcycle';

  List<Map<String, dynamic>> countries = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> zones = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> services = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> requirements = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ExpressRuntimeChannel.previewMode &&
        !diditBusy) {
      _loadDiditState(refresh: true, silent: true);
    }
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  String _text(dynamic value, [String fallback = '']) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? fallback : s;
  }

  Future<Map<String, dynamic>> _catalog({
    String? country,
    String? zone,
    double? lat,
    double? lng,
  }) async {
    final raw = await supabase.rpc(
      'driver_onboarding_catalog',
      params: {
        'p_country_code': country,
        'p_zone_id': zone,
        'p_lat': lat,
        'p_lng': lng,
      },
    );
    return _map(raw);
  }

  Future<void> _load() async {
    try {
      final stateValue = await supabase.rpc('my_driver_onboarding_state');
      final catalogValue = await _catalog();
      final state = _map(stateValue);
      final initialCatalog = _map(catalogValue);
      final profile = _map(state['profile']);
      final vehicle = _map(state['vehicle']);

      approval = _text(profile['approval_status'], 'pending');
      brand.text = _text(vehicle['brand']);
      model.text = _text(vehicle['model']);
      color.text = _text(vehicle['color']);
      plate.text = _text(vehicle['plate']);
      year.text = _text(vehicle['year']);
      profilePhotoPath = profile['profile_photo_path']?.toString();
      vehicleType = _text(vehicle['vehicle_type'], 'motorcycle');
      vehiclePhotoPaths
        ..clear()
        ..addAll(
          vehicle['photo_paths'] is List
              ? (vehicle['photo_paths'] as List).map((e) => e.toString())
              : const <String>[],
        );

      countryCode = _text(profile['country_code']).isEmpty
          ? null
          : _text(profile['country_code']);
      zoneId = profile['zone_id']?.toString();

      selectedServices
        ..clear()
        ..addAll(
          _list(state['services'])
              .where((e) => e['enabled'] != false)
              .map((e) => e['service_key'].toString()),
        );

      countries = _list(initialCatalog['countries']);
      zones = _list(initialCatalog['zones']);

      if (countryCode != null || zoneId != null) {
        await _refreshCatalog(country: countryCode, zone: zoneId);
      } else {
        await _detectLocation(silent: true);
      }

      final existingDocs = _list(state['documents']);
      for (final row in existingDocs) {
        final requirementId = row['requirement_id']?.toString();
        if (requirementId == null || requirementId.isEmpty) continue;
        final draft = _documents.putIfAbsent(
          requirementId,
          () => _DocumentDraft(requirementId),
        );
        draft.number.text = _text(row['document_number']);
        draft.frontPath = row['front_object_path']?.toString();
        draft.backPath = row['back_object_path']?.toString();
        draft.selfiePath = row['selfie_object_path']?.toString();
      }

      if (ExpressRuntimeChannel.previewMode) {
        await _loadDiditState(silent: true);
      }
    } catch (e) {
      if (mounted) _snack('No se pudo cargar el registro de conductor: ' + e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _refreshCatalog({
    String? country,
    String? zone,
    double? lat,
    double? lng,
  }) async {
    final data = await _catalog(
      country: country,
      zone: zone,
      lat: lat,
      lng: lng,
    );
    if (!mounted) return;

    final nextCountries = _list(data['countries']);
    final nextZones = _list(data['zones']);
    final selectedZone = _map(data['selected_zone']);
    final suggested = data['suggested_zone_id']?.toString();

    setState(() {
      if (nextCountries.isNotEmpty) countries = nextCountries;
      zones = nextZones;
      services = _list(data['services']);
      requirements = _list(data['document_requirements']);

      if (country != null && country.trim().isNotEmpty) {
        countryCode = country.toUpperCase();
      }
      if (selectedZone.isNotEmpty) {
        zoneId = selectedZone['id']?.toString();
        countryCode = selectedZone['country_code']?.toString();
      } else if (zone == null && suggested != null && suggested.isNotEmpty) {
        zoneId = suggested;
      }

      _syncDocumentDrafts();
      _syncServiceSelection();
    });
  }

  void _syncDocumentDrafts() {
    for (final requirement in requirements) {
      final id = requirement['id']?.toString();
      if (id == null || id.isEmpty) continue;
      _documents.putIfAbsent(id, () => _DocumentDraft(id));
    }
  }

  void _syncServiceSelection() {
    final allowed = services.map((e) => e['service_key']?.toString()).whereType<String>().toSet();
    selectedServices.removeWhere((key) => !allowed.contains(key));
    if (selectedServices.isEmpty && services.length == 1) {
      selectedServices.add(services.first['service_key'].toString());
      vehicleType = _text(services.first['vehicle_type'], vehicleType);
    }
  }

  Future<String?> _countryCodeFromGps(double latitude, double longitude) async {
    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/reverse',
        {
          'lat': latitude.toString(),
          'lon': longitude.toString(),
          'format': 'jsonv2',
          'zoom': '5',
          'addressdetails': '1',
        },
      );
      final response = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Accept-Language': 'es',
              'User-Agent':
                  'ExpressDelivery/1.5 (https://expressviajes.online)',
            },
          )
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final address = decoded['address'];
      if (address is! Map) return null;
      final raw = address['country_code']?.toString().trim().toUpperCase();
      if (raw == 'BO' || raw == 'CL') return raw;
    } catch (_) {
      // El selector manual siempre queda disponible como respaldo.
    }
    return null;
  }

  Future<void> _detectLocation({bool silent = false}) async {
    if (detecting) return;
    setState(() => detecting = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!silent) _snack('No se pudo usar GPS. Selecciona país y ciudad manualmente.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final detectedCountry = await _countryCodeFromGps(
        position.latitude,
        position.longitude,
      );
      await _refreshCatalog(
        country: detectedCountry,
        lat: position.latitude,
        lng: position.longitude,
      );

      if (!silent && detectedCountry == null) {
        _snack(
          'Detectamos tu ubicación, pero no pudimos identificar el país. Selecciónalo manualmente.',
        );
      } else if (!silent && zoneId == null) {
        _snack('No encontramos una ciudad Express activa cerca. Selecciónala manualmente.');
      }
    } catch (_) {
      if (!silent) _snack('No se pudo detectar la ubicación. Selecciona manualmente.');
    } finally {
      if (mounted) setState(() => detecting = false);
    }
  }

  Future<void> _selectCountry(String? value) async {
    if (value == null) return;
    setState(() {
      countryCode = value;
      zoneId = null;
      services = <Map<String, dynamic>>[];
      requirements = <Map<String, dynamic>>[];
      selectedServices.clear();
    });
    await _refreshCatalog(country: value);
  }

  Future<void> _selectZone(String? value) async {
    if (value == null) return;
    setState(() {
      zoneId = value;
      selectedServices.clear();
    });
    await _refreshCatalog(country: countryCode, zone: value);
  }

  void _toggleService(Map<String, dynamic> service, bool selected) {
    final key = service['service_key']?.toString();
    if (key == null) return;
    final type = _text(service['vehicle_type'], vehicleType);

    setState(() {
      if (selected) {
        final existingType = selectedServices.isEmpty
            ? null
            : _text(
                services.firstWhere(
                  (row) => selectedServices.contains(row['service_key']?.toString()),
                  orElse: () => <String, dynamic>{},
                )['vehicle_type'],
              );
        if (existingType != null && existingType.isNotEmpty && existingType != type) {
          selectedServices.clear();
        }
        selectedServices.add(key);
        vehicleType = type;
      } else {
        selectedServices.remove(key);
      }
    });
  }

  Future<String?> _pickAndUpload({
    required String folder,
    required String slot,
    required ImageSource source,
  }) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 86,
      maxWidth: 2200,
    );
    if (image == null) return null;

    final bytes = await image.readAsBytes();
    if (bytes.length > 15 * 1024 * 1024) {
      _snack('La imagen supera 15 MB.');
      return null;
    }

    final lower = image.name.toLowerCase();
    final ext = lower.endsWith('.png')
        ? 'png'
        : lower.endsWith('.webp')
            ? 'webp'
            : 'jpg';
    final contentType = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
            ? 'image/webp'
            : 'image/jpeg';

    final path = widget.service.userId +
        '/' +
        folder +
        '/' +
        slot +
        '-' +
        DateTime.now().millisecondsSinceEpoch.toString() +
        '.' +
        ext;

    await supabase.storage.from('driver-onboarding').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
            cacheControl: '3600',
          ),
        );
    return path;
  }

  Future<ImageSource?> _sourceSheet(String title) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.photo_camera_outlined)),
                title: const Text('Tomar una foto'),
                subtitle: const Text('Usar la cámara del teléfono'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.photo_library_outlined)),
                title: const Text('Elegir de la galería'),
                subtitle: const Text('Seleccionar una imagen existente'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickProfilePhoto() async {
    final source = await _sourceSheet('Foto de perfil');
    if (source == null) return;
    setState(() => saving = true);
    try {
      final path = await _pickAndUpload(folder: 'profile', slot: 'profile', source: source);
      if (path != null && mounted) setState(() => profilePhotoPath = path);
    } catch (e) {
      _snack('No se pudo subir la foto: ' + e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _addVehiclePhoto() async {
    if (vehiclePhotoPaths.length >= 4) {
      _snack('Puedes cargar hasta 4 fotos del vehículo.');
      return;
    }
    final source = await _sourceSheet('Foto del vehículo');
    if (source == null) return;
    setState(() => saving = true);
    try {
      final path = await _pickAndUpload(
        folder: 'vehicle',
        slot: 'vehicle-' + vehiclePhotoPaths.length.toString(),
        source: source,
      );
      if (path != null && mounted) setState(() => vehiclePhotoPaths.add(path));
    } catch (e) {
      _snack('No se pudo subir la foto: ' + e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickDocument(
    Map<String, dynamic> requirement,
    String slot,
  ) async {
    final id = requirement['id']?.toString();
    if (id == null) return;
    final source = await _sourceSheet(_text(requirement['label'], 'Documento'));
    if (source == null) return;

    setState(() => saving = true);
    try {
      final path = await _pickAndUpload(
        folder: 'documents/' + id,
        slot: slot,
        source: source,
      );
      if (path == null) return;
      final draft = _documents.putIfAbsent(id, () => _DocumentDraft(id));
      setState(() {
        if (slot == 'front') draft.frontPath = path;
        if (slot == 'back') draft.backPath = path;
        if (slot == 'selfie') draft.selfiePath = path;
      });
    } catch (e) {
      _snack('No se pudo subir el documento: ' + e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _diditStatus() =>
      _text(diditVerification['status']).toLowerCase();

  String _diditProviderStatus() =>
      _text(diditVerification['provider_status']);

  Future<void> _loadDiditState({
    bool refresh = false,
    bool silent = false,
  }) async {
    if (!ExpressRuntimeChannel.previewMode) return;
    if (!silent && mounted) setState(() => diditBusy = true);
    try {
      final response = await supabase.functions.invoke(
        'didit-identity',
        body: {'action': refresh ? 'refresh' : 'state'},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (data['ok'] != true) {
        throw StateError(
          data['error']?.toString() ?? 'No se pudo consultar Didit',
        );
      }
      final verification = data['verification'] is Map
          ? Map<String, dynamic>.from(data['verification'] as Map)
          : <String, dynamic>{};
      if (mounted) {
        setState(() {
          diditVerification = verification;
          diditError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => diditError = e.toString());
        if (!silent) _snack('Didit Sandbox: ' + e.toString());
      }
    } finally {
      if (!silent && mounted) setState(() => diditBusy = false);
    }
  }

  Future<void> _startDiditVerification() async {
    if (!ExpressRuntimeChannel.previewMode || diditBusy) return;
    setState(() {
      diditBusy = true;
      diditError = null;
    });
    try {
      final response = await supabase.functions.invoke(
        'didit-identity',
        body: const {'action': 'create'},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (data['ok'] != true) {
        throw StateError(
          data['error']?.toString() ??
              'No se pudo crear la verificación Didit',
        );
      }
      final rawUrl = _text(data['url']);
      if (rawUrl.isEmpty) {
        throw StateError('Didit no devolvió el enlace de verificación');
      }
      final uri = Uri.tryParse(rawUrl);
      if (uri == null) throw StateError('Enlace Didit inválido');

      if (mounted) {
        setState(() {
          diditVerification = <String, dynamic>{
            ...diditVerification,
            'provider': 'didit',
            'provider_environment': 'sandbox',
            'provider_session_id': data['session_id'],
            'verification_url': rawUrl,
            'status': data['status'] ?? 'pending',
          };
        });
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('No se pudo abrir Didit');
      }
    } catch (e) {
      if (mounted) {
        setState(() => diditError = e.toString());
        _snack('Didit Sandbox: ' + e.toString());
      }
    } finally {
      if (mounted) setState(() => diditBusy = false);
    }
  }

  Widget _diditCard() {
    final status = _diditStatus();
    final verified = status == 'verified';
    final rejected = status == 'rejected';
    final review = status == 'review';
    final hasSession =
        _text(diditVerification['provider_session_id']).isNotEmpty;

    final Color accent = verified
        ? const Color(0xFF067647)
        : rejected
            ? const Color(0xFFB42318)
            : review
                ? const Color(0xFFB54708)
                : const Color(0xFF0B57D0);
    final Color background = verified
        ? const Color(0xFFECFDF3)
        : rejected
            ? const Color(0xFFFEF3F2)
            : review
                ? const Color(0xFFFFFAEB)
                : const Color(0xFFEAF2FF);

    final String title = verified
        ? 'Identidad verificada'
        : rejected
            ? 'Verificación rechazada'
            : review
                ? 'Verificación en revisión'
                : hasSession
                    ? 'Verificación Didit pendiente'
                    : 'Verificar identidad con Didit';

    final String detail = verified
        ? 'Documento, prueba de vida y coincidencia facial aprobados en Sandbox.'
        : rejected
            ? 'Didit rechazó la prueba. Puedes reintentar o usar la revisión manual.'
            : review
                ? 'Didit envió la verificación a revisión.'
                : 'Sandbox · Documento + prueba de vida + coincidencia facial. La selfie biométrica no se usa como foto de perfil.';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: accent.withOpacity(.12),
                foregroundColor: accent,
                child: Icon(
                  verified
                      ? Icons.verified_user_rounded
                      : Icons.face_retouching_natural_rounded,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: Color(0xFF475467),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Chip(label: Text('SANDBOX')),
            ],
          ),
          if (_diditProviderStatus().isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.info_outline_rounded,
              text: 'Didit: ' + _diditProviderStatus(),
            ),
          ],
          if (diditError != null && diditError!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              diditError!,
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: diditBusy ? null : _startDiditVerification,
                icon: diditBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.open_in_new_rounded),
                label: Text(
                  verified
                      ? 'Verificar nuevamente'
                      : hasSession
                          ? 'Continuar verificación'
                          : 'Comenzar verificación',
                ),
              ),
              if (hasSession)
                OutlinedButton.icon(
                  onPressed: diditBusy
                      ? null
                      : () => _loadDiditState(refresh: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Actualizar estado'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _stepValid(int value, {bool showMessage = true}) {
    String? message;
    if (value == 0) {
      if (countryCode == null || zoneId == null) {
        message = 'Selecciona país y ciudad.';
      } else if (selectedServices.isEmpty) {
        message = 'Selecciona al menos un servicio activo de la ciudad.';
      }
    } else if (value == 1) {
      if (profilePhotoPath == null || profilePhotoPath!.isEmpty) {
        message = 'Sube tu foto de perfil.';
      }
    } else if (value == 2) {
      if (brand.text.trim().isEmpty ||
          model.text.trim().isEmpty ||
          plate.text.trim().isEmpty) {
        message = 'Completa marca, modelo y placa.';
      } else if (vehiclePhotoPaths.isEmpty) {
        message = 'Sube al menos una foto del vehículo.';
      }
    } else if (value == 3) {
      for (final requirement in requirements) {
        if (requirement['required'] != true) continue;
        final id = requirement['id']?.toString();
        if (id == null) continue;
        final draft = _documents[id] ?? _DocumentDraft(id);
        final label = _text(requirement['label'], 'Documento');
        if (requirement['require_number'] == true && draft.number.text.trim().isEmpty) {
          message = 'Completa el número de ' + label + '.';
          break;
        }
        if (requirement['require_front'] == true && (draft.frontPath?.isNotEmpty != true)) {
          message = 'Sube el frente de ' + label + '.';
          break;
        }
        if (requirement['require_back'] == true && (draft.backPath?.isNotEmpty != true)) {
          message = 'Sube el reverso de ' + label + '.';
          break;
        }
        if (requirement['require_selfie'] == true && (draft.selfiePath?.isNotEmpty != true)) {
          message = 'Toma la selfie solicitada para ' + label + '.';
          break;
        }
      }
    }

    if (message != null && showMessage) _snack(message);
    return message == null;
  }

  Future<void> _continue() async {
    if (!_stepValid(step)) return;
    if (step < 4) setState(() => step++);
  }

  void _back() {
    if (step > 0) setState(() => step--);
  }

  String _documentNumberForCode(String code) {
    for (final requirement in requirements) {
      if (_text(requirement['code']) != code) continue;
      final id = requirement['id']?.toString();
      if (id == null || id.isEmpty) continue;
      return _documents[id]?.number.text.trim() ?? '';
    }
    return '';
  }

  Future<void> _submit() async {
    for (var i = 0; i <= 3; i++) {
      if (!_stepValid(i)) {
        setState(() => step = i);
        return;
      }
    }

    final vehicleYear = year.text.trim().isEmpty ? null : int.tryParse(year.text.trim());
    if (year.text.trim().isNotEmpty && vehicleYear == null) {
      _snack('El año del vehículo no es válido.');
      setState(() => step = 2);
      return;
    }

    final docs = <Map<String, dynamic>>[];
    for (final requirement in requirements) {
      final id = requirement['id']?.toString();
      if (id == null) continue;
      final draft = _documents[id];
      if (draft == null) continue;
      docs.add({
        'requirement_id': id,
        'document_type': _text(requirement['code'], 'document'),
        'document_number': draft.number.text.trim(),
        'front_object_path': draft.frontPath,
        'back_object_path': draft.backPath,
        'selfie_object_path': draft.selfiePath,
      });
    }

    setState(() => saving = true);
    try {
      final result = await supabase.rpc(
        'submit_driver_onboarding',
        params: {
          'p_zone_id': zoneId,
          'p_license_number': _documentNumberForCode('driver_license'),
          'p_service_keys': selectedServices.toList(),
          'p_vehicle_type': vehicleType,
          'p_vehicle_brand': brand.text.trim(),
          'p_vehicle_model': model.text.trim(),
          'p_vehicle_color': color.text.trim(),
          'p_vehicle_plate': plate.text.trim(),
          'p_vehicle_year': vehicleYear,
          'p_profile_photo_path': profilePhotoPath,
          'p_vehicle_photo_paths': vehiclePhotoPaths,
          'p_documents': docs,
        },
      );
      if (!mounted) return;
      setState(() => approval = 'pending');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.verified_user_outlined, size: 42),
          title: const Text('Registro enviado'),
          content: const Text(
            'Recibimos tus datos, fotos y documentos. Un administrador revisará la información antes de habilitarte para recibir solicitudes.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      _snack('No se pudo enviar el registro: ' + e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _snack(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  String _countryName(String code) {
    final row = countries.cast<Map<String, dynamic>?>().firstWhere(
          (e) => e?['code']?.toString() == code,
          orElse: () => null,
        );
    return row?['name']?.toString() ?? code;
  }

  String _zoneName(String id) {
    final row = zones.cast<Map<String, dynamic>?>().firstWhere(
          (e) => e?['id']?.toString() == id,
          orElse: () => null,
        );
    return row?['city']?.toString() ?? row?['name']?.toString() ?? id;
  }

  Widget _statusCard() {
    final approved = approval == 'approved';
    final tone = approved ? const Color(0xFF067647) : const Color(0xFFB54708);
    final bg = approved ? const Color(0xFFECFDF3) : const Color(0xFFFFFAEB);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withOpacity(.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: tone.withOpacity(.12),
            foregroundColor: tone,
            child: Icon(approved ? Icons.verified_rounded : Icons.hourglass_top_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  approved ? 'Conductor aprobado' : 'Registro de conductor',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  approved
                      ? 'Puedes actualizar tus datos cuando sea necesario.'
                      : 'Completa los pasos. Tus documentos quedarán en revisión antes de recibir solicitudes.',
                  style: const TextStyle(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HintCard(
          icon: Icons.my_location_rounded,
          title: 'Detectamos tu zona con GPS',
          text: 'Express usa tu ubicación solo para sugerir el país y la ciudad operativa. También puedes cambiarla manualmente.',
          action: TextButton.icon(
            onPressed: detecting ? null : () => _detectLocation(),
            icon: detecting
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.gps_fixed_rounded),
            label: Text(detecting ? 'Detectando...' : 'Detectar de nuevo'),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: countryCode,
          decoration: const InputDecoration(
            labelText: 'País',
            prefixIcon: Icon(Icons.public_rounded),
          ),
          items: countries
              .map(
                (row) => DropdownMenuItem<String>(
                  value: row['code']?.toString(),
                  child: Text(row['name']?.toString() ?? row['code'].toString()),
                ),
              )
              .toList(),
          onChanged: saving ? null : _selectCountry,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: zoneId,
          decoration: const InputDecoration(
            labelText: 'Ciudad',
            prefixIcon: Icon(Icons.location_city_rounded),
          ),
          items: zones
              .map(
                (row) => DropdownMenuItem<String>(
                  value: row['id']?.toString(),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(row['city']?.toString() ?? row['name'].toString()),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: countryCode == null || saving ? null : _selectZone,
        ),
        const SizedBox(height: 18),
        const Text('Servicios activos en esta ciudad', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(
          zoneId == null
              ? 'Selecciona una ciudad para ver sus servicios.'
              : services.isEmpty
                  ? 'No hay servicios de conductor activos en esta ciudad.'
                  : 'Solo verás servicios habilitados para ' + _zoneName(zoneId!) + '.',
          style: const TextStyle(color: Color(0xFF667085)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: services.map((service) {
            final key = service['service_key']?.toString() ?? '';
            final selected = selectedServices.contains(key);
            return FilterChip(
              selected: selected,
              avatar: Icon(
                _vehicleIcon(_text(service['vehicle_type'])),
                size: 18,
              ),
              label: Text(_text(service['name'], key)),
              onSelected: saving ? null : (value) => _toggleService(service, value),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _profileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UploadTile(
          icon: Icons.account_circle_outlined,
          title: 'Foto de perfil',
          subtitle: profilePhotoPath == null
              ? 'Obligatoria · rostro visible y buena iluminación'
              : 'Foto cargada correctamente',
          complete: profilePhotoPath != null,
          onTap: saving ? null : _pickProfilePhoto,
        ),
        const SizedBox(height: 12),
        if (countryCode != null && zoneId != null)
          _InfoLine(
            icon: Icons.pin_drop_outlined,
            text: _countryName(countryCode!) + ' · ' + _zoneName(zoneId!),
          ),
      ],
    );
  }

  Widget _vehicleStep() {
    final selectedNames = services
        .where((e) => selectedServices.contains(e['service_key']?.toString()))
        .map((e) => _text(e['name']))
        .where((e) => e.isNotEmpty)
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedNames.isNotEmpty)
          _HintCard(
            icon: _vehicleIcon(vehicleType),
            title: 'Vehículo para ' + selectedNames,
            text: 'El tipo se determina por los servicios activos de la ciudad seleccionada.',
          ),
        const SizedBox(height: 12),
        TextField(controller: brand, decoration: const InputDecoration(labelText: 'Marca')),
        const SizedBox(height: 12),
        TextField(controller: model, decoration: const InputDecoration(labelText: 'Modelo')),
        const SizedBox(height: 12),
        TextField(controller: color, decoration: const InputDecoration(labelText: 'Color')),
        const SizedBox(height: 12),
        TextField(controller: plate, decoration: const InputDecoration(labelText: 'Placa')),
        const SizedBox(height: 12),
        TextField(
          controller: year,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Año'),
        ),
        const SizedBox(height: 14),
        _UploadTile(
          icon: Icons.directions_car_filled_outlined,
          title: 'Fotos del vehículo',
          subtitle: vehiclePhotoPaths.isEmpty
              ? 'Agrega al menos una foto. Puedes subir hasta 4.'
              : vehiclePhotoPaths.length.toString() + ' foto(s) cargada(s)',
          complete: vehiclePhotoPaths.isNotEmpty,
          onTap: saving ? null : _addVehiclePhoto,
        ),
        if (vehiclePhotoPaths.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < vehiclePhotoPaths.length; i++)
                InputChip(
                  label: Text('Foto ' + (i + 1).toString()),
                  avatar: const Icon(Icons.image_outlined, size: 18),
                  onDeleted: saving
                      ? null
                      : () => setState(() => vehiclePhotoPaths.removeAt(i)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _documentsStep() {
    if (requirements.isEmpty) {
      return const _HintCard(
        icon: Icons.description_outlined,
        title: 'Sin documentos configurados',
        text: 'El administrador todavía no configuró documentos obligatorios para esta ciudad.',
      );
    }
    return Column(
      children: [
        if (ExpressRuntimeChannel.previewMode) _diditCard(),
        ...requirements.map((requirement) {
        final id = requirement['id']?.toString() ?? '';
        final draft = _documents.putIfAbsent(id, () => _DocumentDraft(id));
        final required = requirement['required'] == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDDE3EC)),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFEAF2FF),
                      child: Icon(Icons.badge_outlined, color: Color(0xFF0B57D0)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_text(requirement['label'], 'Documento'), style: const TextStyle(fontWeight: FontWeight.w900)),
                          if (_text(requirement['description']).isNotEmpty)
                            Text(_text(requirement['description']), style: const TextStyle(color: Color(0xFF667085))),
                        ],
                      ),
                    ),
                    if (required)
                      const Chip(label: Text('Obligatorio')),
                  ],
                ),
                if (requirement['require_number'] == true) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: draft.number,
                    decoration: const InputDecoration(labelText: 'Número del documento'),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (requirement['require_front'] == true)
                      _DocButton(
                        label: 'Frente',
                        complete: draft.frontPath?.isNotEmpty == true,
                        icon: Icons.credit_card_rounded,
                        onPressed: saving ? null : () => _pickDocument(requirement, 'front'),
                      ),
                    if (requirement['require_back'] == true)
                      _DocButton(
                        label: 'Reverso',
                        complete: draft.backPath?.isNotEmpty == true,
                        icon: Icons.flip_to_back_rounded,
                        onPressed: saving ? null : () => _pickDocument(requirement, 'back'),
                      ),
                    if (requirement['require_selfie'] == true)
                      _DocButton(
                        label: 'Selfie',
                        complete: draft.selfiePath?.isNotEmpty == true,
                        icon: Icons.face_retouching_natural_rounded,
                        onPressed: saving ? null : () => _pickDocument(requirement, 'selfie'),
                      ),
                  ],
                ),
                if (requirement['require_selfie'] == true) ...[
                  const SizedBox(height: 10),
                  const _InfoLine(
                    icon: Icons.security_rounded,
                    text: 'La selfie queda preparada para comparar el rostro con el documento.',
                  ),
                ],
              ],
            ),
          ),
        );
      }),
      ],
    );
  }

  Widget _reviewStep() {
    final serviceNames = services
        .where((e) => selectedServices.contains(e['service_key']?.toString()))
        .map((e) => _text(e['name']))
        .where((e) => e.isNotEmpty)
        .join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HintCard(
          icon: Icons.fact_check_outlined,
          title: 'Revisa antes de enviar',
          text: 'Tu cuenta quedará pendiente hasta que un administrador revise los documentos y el vehículo.',
        ),
        const SizedBox(height: 14),
        _ReviewRow('País', countryCode == null ? '—' : _countryName(countryCode!)),
        _ReviewRow('Ciudad', zoneId == null ? '—' : _zoneName(zoneId!)),
        _ReviewRow('Servicios', serviceNames.isEmpty ? '—' : serviceNames),
        _ReviewRow(
          'Licencia',
          _documentNumberForCode('driver_license').isEmpty
              ? '—'
              : _documentNumberForCode('driver_license'),
        ),
        _ReviewRow('Vehículo', (brand.text.trim() + ' ' + model.text.trim()).trim()),
        _ReviewRow('Placa', plate.text.trim().isEmpty ? '—' : plate.text.trim()),
        _ReviewRow('Documentos', requirements.length.toString() + ' requisito(s)'),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: true,
          onChanged: null,
          contentPadding: EdgeInsets.zero,
          title: const Text('Confirmo que la información y documentos son reales.'),
          subtitle: const Text('La aprobación puede rechazarse si los datos no coinciden.'),
        ),
      ],
    );
  }

  IconData _vehicleIcon(String type) {
    switch (type) {
      case 'car':
        return Icons.directions_car_filled_rounded;
      case 'van':
      case 'truck':
        return Icons.local_shipping_rounded;
      default:
        return Icons.two_wheeler_rounded;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    brand.dispose();
    model.dispose();
    color.dispose();
    plate.dispose();
    year.dispose();
    for (final draft in _documents.values) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Registro de conductor'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  _statusCard(),
                  const SizedBox(height: 14),
                  Stepper(
                    currentStep: step,
                    onStepTapped: saving ? null : (value) => setState(() => step = value),
                    controlsBuilder: (_, __) => const SizedBox.shrink(),
                    physics: const NeverScrollableScrollPhysics(),
                    steps: [
                      Step(
                        title: const Text('País, ciudad y servicios'),
                        subtitle: const Text('GPS + disponibilidad local'),
                        isActive: step >= 0,
                        state: step > 0 ? StepState.complete : StepState.indexed,
                        content: _locationStep(),
                      ),
                      Step(
                        title: const Text('Perfil'),
                        subtitle: const Text('Foto personal'),
                        isActive: step >= 1,
                        state: step > 1 ? StepState.complete : StepState.indexed,
                        content: _profileStep(),
                      ),
                      Step(
                        title: const Text('Vehículo'),
                        subtitle: const Text('Datos y fotografías'),
                        isActive: step >= 2,
                        state: step > 2 ? StepState.complete : StepState.indexed,
                        content: _vehicleStep(),
                      ),
                      Step(
                        title: const Text('Documentos'),
                        subtitle: const Text('Requisitos de tu ciudad'),
                        isActive: step >= 3,
                        state: step > 3 ? StepState.complete : StepState.indexed,
                        content: _documentsStep(),
                      ),
                      Step(
                        title: const Text('Revisar y enviar'),
                        subtitle: const Text('Solicitud de aprobación'),
                        isActive: step >= 4,
                        content: _reviewStep(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE4E7EC))),
              ),
              child: Row(
                children: [
                  if (step > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: saving ? null : _back,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Atrás'),
                      ),
                    ),
                  if (step > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: saving ? null : (step == 4 ? _submit : _continue),
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(step == 4 ? Icons.send_rounded : Icons.arrow_forward_rounded),
                      label: Text(step == 4 ? 'Enviar para aprobación' : 'Continuar'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: const Color(0xFF0B57D0),
                      ),
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

class _DocumentDraft {
  final String requirementId;
  final TextEditingController number = TextEditingController();
  String? frontPath;
  String? backPath;
  String? selfiePath;

  _DocumentDraft(this.requirementId);

  void dispose() => number.dispose();
}

class _HintCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  const _HintCard({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0B57D0)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(text, style: const TextStyle(color: Color(0xFF475467), height: 1.35)),
                if (action != null) ...[
                  const SizedBox(height: 4),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool complete;
  final VoidCallback? onTap;

  const _UploadTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.complete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: complete ? const Color(0xFFECFDF3) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: complete ? const Color(0xFFABEFC6) : const Color(0xFFDDE3EC),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: complete ? const Color(0xFFD1FADF) : const Color(0xFFEAF2FF),
                child: Icon(
                  complete ? Icons.check_rounded : icon,
                  color: complete ? const Color(0xFF067647) : const Color(0xFF0B57D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: Color(0xFF667085))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocButton extends StatelessWidget {
  final String label;
  final bool complete;
  final IconData icon;
  final VoidCallback? onPressed;

  const _DocButton({
    required this.label,
    required this.complete,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(complete ? Icons.check_circle_rounded : icon),
      label: Text(complete ? label + ' ✓' : label),
      style: OutlinedButton.styleFrom(
        foregroundColor: complete ? const Color(0xFF067647) : const Color(0xFF0B57D0),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF667085)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF667085)))),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEAECF0))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 105,
            child: Text(label, style: const TextStyle(color: Color(0xFF667085))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:didit_sdk_autodetection/sdk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'services/express_service.dart';

class DriverSetupPage extends StatefulWidget {
  final ExpressService service;
  final bool editExisting;
  final int initialStep;
  final String? focusSection;

  const DriverSetupPage({
    super.key,
    required this.service,
    this.editExisting = false,
    this.initialStep = 0,
    this.focusSection,
  });

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
    step = widget.initialStep.clamp(0, 4).toInt();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !diditBusy) {
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

  bool get _focusedEdit =>
      widget.editExisting && (widget.focusSection?.trim().isNotEmpty ?? false);

  bool _identityRequirement(Map<String, dynamic> requirement) {
    final code = _text(requirement['code']).toLowerCase();
    final label = _text(requirement['label']).toLowerCase();
    const tokens = <String>[
      'identity',
      'national_id',
      'id_card',
      'carnet',
      'cedula',
      'cédula',
      'documento de identidad',
    ];
    return tokens.any(
      (token) => code.contains(token) || label.contains(token),
    );
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

      await _loadDiditState(silent: true);

      // Cuando el flujo de cambio de modo abre esta pantalla y el backend ya
      // reconoce al conductor como aprobado, no debemos volver a mostrarle el
      // onboarding. La edición manual sigue disponible desde Perfil usando
      // editExisting=true.
      if (approval.trim().toLowerCase() == 'approved' &&
          !widget.editExisting &&
          mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pop(<String, dynamic>{
            'approval_status': 'approved',
          });
        });
      }
    } catch (e) {
      if (mounted) {
        _snack(
          ExpressRuntimeChannel.userSafeError(
            e,
            fallback: 'No se pudo cargar el registro de conductor. Intenta nuevamente.',
          ),
        );
      }
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
      _snack(
        ExpressRuntimeChannel.userSafeError(
          e,
          fallback: 'No se pudo subir la foto. Intenta nuevamente.',
        ),
      );
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
      _snack(
        ExpressRuntimeChannel.userSafeError(
          e,
          fallback: 'No se pudo subir el documento. Intenta nuevamente.',
        ),
      );
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
    if (!silent && mounted) setState(() => diditBusy = true);
    try {
      final response = await supabase.functions.invoke(
        ExpressRuntimeChannel.previewMode
            ? 'didit-identity'
            : 'didit-identity-prod',
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
          final diditProfilePath = _text(data['profile_photo_path']);
          if (diditProfilePath.isNotEmpty) {
            profilePhotoPath = diditProfilePath;
          }
          diditError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => diditError = e.toString());
        if (!silent) {
          _snack(
            ExpressRuntimeChannel.userSafeError(
              e,
              fallback:
                  'No se pudo consultar la verificación de identidad. Intenta nuevamente.',
            ),
          );
        }
      }
    } finally {
      if (!silent && mounted) setState(() => diditBusy = false);
    }
  }

  Future<void> _startDiditVerification() async {
    if (diditBusy) return;
    setState(() {
      diditBusy = true;
      diditError = null;
    });
    try {
      final response = await supabase.functions.invoke(
        ExpressRuntimeChannel.previewMode
            ? 'didit-identity'
            : 'didit-identity-prod',
        body: {
          'action': 'create',
          'zone_id': zoneId,
        },
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
      final sessionToken = _text(data['session_token']);
      if (sessionToken.isEmpty) {
        throw StateError(
          'Didit no devolvió el token seguro para iniciar la verificación',
        );
      }
      final rawUrl = _text(data['url']);

      if (mounted) {
        setState(() {
          diditVerification = <String, dynamic>{
            ...diditVerification,
            'provider': 'didit',
            'provider_environment':
                ExpressRuntimeChannel.previewMode ? 'sandbox' : 'production',
            'provider_session_id': data['session_id'],
            if (rawUrl.isNotEmpty) 'verification_url': rawUrl,
            'status': data['status'] ?? 'pending',
          };
        });
      }

      final result = await DiditSdk.startVerification(
        sessionToken,
        config: DiditConfig(
          languageCode: 'es',
          showLanguageSelector: false,
          loggingEnabled: ExpressRuntimeChannel.previewMode,
          showCloseButton: true,
          showExitConfirmation: true,
          closeOnComplete: true,
        ),
      );

      if (result is VerificationCancelled) {
        await _loadDiditState(refresh: true, silent: true);
        if (mounted) {
          _snack('Verificación cancelada. Puedes continuar cuando quieras.');
        }
        return;
      }

      if (result is VerificationFailed) {
        throw StateError(
          'Didit no pudo completar la verificación: ${result.error.message}',
        );
      }

      // El SDK solo controla la experiencia de cámara dentro de la app.
      // El estado confiable siempre se reconcilia contra Didit/Supabase.
      await _loadDiditState(refresh: true);
    } catch (e) {
      if (mounted) {
        setState(() => diditError = e.toString());
        _snack(
          ExpressRuntimeChannel.userSafeError(
            e,
            fallback:
                'No se pudo completar la verificación de identidad. Intenta nuevamente.',
          ),
        );
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
                    ? (ExpressRuntimeChannel.previewMode
                        ? 'Verificación Didit pendiente'
                        : 'Verificación de identidad pendiente')
                    : (ExpressRuntimeChannel.previewMode
                        ? 'Verificar identidad con Didit'
                        : 'Verificar identidad');

    final environmentLabel =
        ExpressRuntimeChannel.previewMode ? 'Sandbox' : 'Producción';
    final String detail = verified
        ? ExpressRuntimeChannel.technicalOr(
            production:
                'Documento, prueba de vida y coincidencia facial aprobados.',
            preview:
                'Documento, prueba de vida y coincidencia facial aprobados en $environmentLabel.',
          )
        : rejected
            ? ExpressRuntimeChannel.technicalOr(
                production:
                    'La verificación fue rechazada. Puedes intentarlo nuevamente.',
                preview:
                    'Didit rechazó la prueba. Puedes reintentar o usar la revisión manual.',
              )
            : review
                ? ExpressRuntimeChannel.technicalOr(
                    production:
                        'Tu verificación está siendo revisada.',
                    preview: 'Didit envió la verificación a revisión.',
                  )
                : ExpressRuntimeChannel.technicalOr(
                    production:
                        'Documento, prueba de vida y coincidencia facial.',
                    preview:
                        '$environmentLabel · Documento + prueba de vida + coincidencia facial.',
                  );

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
              if (ExpressRuntimeChannel.previewMode)
                const Chip(
                  label: Text('SANDBOX'),
                ),
            ],
          ),
          if (ExpressRuntimeChannel.previewMode &&
              _diditProviderStatus().isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.info_outline_rounded,
              text: 'Didit: ' + _diditProviderStatus(),
            ),
          ],
          if (ExpressRuntimeChannel.previewMode &&
              diditError != null &&
              diditError!.isNotEmpty) ...[
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
                    : const Icon(Icons.verified_user_rounded),
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
      final useVerifiedDiditProfile =
          !ExpressRuntimeChannel.previewMode && countryCode == 'BO';
      if (useVerifiedDiditProfile) {
        if (_diditStatus() != 'verified') {
          message = 'Completa la verificación de identidad con Didit.';
        } else if (profilePhotoPath == null || profilePhotoPath!.isEmpty) {
          message = 'Estamos preparando tu foto de perfil verificada. Actualiza el estado.';
        }
      } else if (profilePhotoPath == null || profilePhotoPath!.isEmpty) {
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
    final useVerifiedDiditProfile =
        !ExpressRuntimeChannel.previewMode && countryCode == 'BO';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (useVerifiedDiditProfile) ...[
          _diditCard(),
          _InfoLine(
            icon: Icons.account_circle_outlined,
            text: ExpressRuntimeChannel.technicalOr(
              production:
                  'La selfie verificada se utilizará como foto de perfil de Express.',
              preview:
                  'La selfie aprobada por Didit se utilizará como foto de perfil de Express.',
            ),
          ),
        ] else ...[
          if (ExpressRuntimeChannel.previewMode) _diditCard(),
          _UploadTile(
            icon: Icons.account_circle_outlined,
            title: 'Foto de perfil',
            subtitle: profilePhotoPath == null
                ? 'Obligatoria · rostro visible y buena iluminación'
                : 'Foto cargada correctamente',
            complete: profilePhotoPath != null,
            onTap: saving ? null : _pickProfilePhoto,
          ),
        ],
        const SizedBox(height: 12),
        if (countryCode != null && zoneId != null)
          _InfoLine(
            icon: Icons.pin_drop_outlined,
            text: _countryName(countryCode!) + ' · ' + _zoneName(zoneId!),
          ),
      ],
    );
  }

  Widget _focusedIdentityStep() {
    final verified = _diditStatus() == 'verified';
    final useVerifiedDiditProfile =
        !ExpressRuntimeChannel.previewMode && countryCode == 'BO';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _diditCard(),
        const SizedBox(height: 14),
        _UploadTile(
          icon: Icons.account_circle_outlined,
          title: 'Foto de perfil',
          subtitle: profilePhotoPath == null || profilePhotoPath!.isEmpty
              ? (useVerifiedDiditProfile
                  ? 'Se obtiene de tu verificación de identidad.'
                  : 'Obligatoria · rostro visible y buena iluminación')
              : 'Foto de perfil registrada correctamente',
          complete: profilePhotoPath?.isNotEmpty == true,
          onTap: saving || useVerifiedDiditProfile
              ? null
              : _pickProfilePhoto,
        ),
        if (useVerifiedDiditProfile && !verified) ...[
          const SizedBox(height: 10),
          const _InfoLine(
            icon: Icons.info_outline_rounded,
            text:
                'Completa la verificación de identidad para actualizar tu foto de perfil verificada.',
          ),
        ],
      ],
    );
  }

  Widget _focusedProfilePhotoStep() {
    final useVerifiedDiditProfile =
        !ExpressRuntimeChannel.previewMode && countryCode == 'BO';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UploadTile(
          icon: Icons.account_circle_outlined,
          title: 'Foto de perfil',
          subtitle: profilePhotoPath == null || profilePhotoPath!.isEmpty
              ? (useVerifiedDiditProfile
                  ? 'Tu foto se obtiene de la verificación de identidad.'
                  : 'Sube una foto con el rostro visible y buena iluminación.')
              : 'Foto de perfil registrada correctamente',
          complete: profilePhotoPath?.isNotEmpty == true,
          onTap: saving || useVerifiedDiditProfile
              ? null
              : _pickProfilePhoto,
        ),
        if (useVerifiedDiditProfile) ...[
          const SizedBox(height: 10),
          const _InfoLine(
            icon: Icons.verified_user_outlined,
            text:
                'Por seguridad, la foto oficial del conductor proviene de la verificación de identidad.',
          ),
        ],
      ],
    );
  }

  Widget _focusedLocationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HintCard(
          icon: Icons.public_rounded,
          title: 'País y zona de trabajo',
          text:
              'Si cambias de país o ciudad, tu cuenta de conductor volverá a revisión antes de recibir solicitudes.',
          action: TextButton.icon(
            onPressed: detecting ? null : () => _detectLocation(),
            icon: detecting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.gps_fixed_rounded),
            label: Text(detecting ? 'Detectando...' : 'Usar mi ubicación'),
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
                  child: Text(
                    row['name']?.toString() ?? row['code'].toString(),
                  ),
                ),
              )
              .toList(),
          onChanged: saving ? null : _selectCountry,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: zoneId,
          decoration: const InputDecoration(
            labelText: 'Zona / ciudad',
            prefixIcon: Icon(Icons.location_city_rounded),
          ),
          items: zones
              .map(
                (row) => DropdownMenuItem<String>(
                  value: row['id']?.toString(),
                  child: Text(
                    row['city']?.toString() ?? row['name'].toString(),
                  ),
                ),
              )
              .toList(),
          onChanged: countryCode == null || saving ? null : _selectZone,
        ),
      ],
    );
  }

  Widget _focusedDocumentsStep() {
    final extra = requirements.where((row) => !_identityRequirement(row)).toList();
    if (extra.isEmpty) {
      return const _HintCard(
        icon: Icons.description_outlined,
        title: 'Sin documentos adicionales',
        text: 'Tu zona no tiene documentos adicionales configurados.',
      );
    }
    final original = requirements;
    requirements = extra;
    final widget = _documentsStep();
    requirements = original;
    return widget;
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

  Future<void> _saveFocusedLocation() async {
    if (zoneId == null || zoneId!.isEmpty) {
      _snack('Selecciona país y zona.');
      return;
    }
    setState(() => saving = true);
    try {
      final result = await supabase.rpc(
        'request_my_driver_zone_change',
        params: {'p_zone_id': zoneId},
      );
      if (!mounted) return;
      setState(() => approval = 'pending');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.hourglass_top_rounded),
          title: const Text('Cambio enviado a revisión'),
          content: Text(
            'Actualizamos tu zona a ' +
                _zoneName(zoneId!) +
                '. Tu cuenta quedará en revisión antes de volver a recibir solicitudes.',
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
      _snack(
        ExpressRuntimeChannel.userSafeError(
          e,
          fallback: 'No se pudo cambiar la zona. Intenta nuevamente.',
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _saveFocusedProfilePhoto() async {
    if (profilePhotoPath == null || profilePhotoPath!.isEmpty) {
      _snack('Sube una foto de perfil.');
      return;
    }
    setState(() => saving = true);
    try {
      final result = await supabase.rpc(
        'update_my_driver_profile_photo_for_review',
        params: {'p_profile_photo_path': profilePhotoPath},
      );
      if (!mounted) return;
      setState(() => approval = 'pending');
      Navigator.pop(context, result);
    } catch (e) {
      _snack(
        ExpressRuntimeChannel.userSafeError(
          e,
          fallback: 'No se pudo guardar la foto de perfil.',
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _saveFocusedVehicle() async {
    if (!_stepValid(2)) return;
    final vehicleYear =
        year.text.trim().isEmpty ? null : int.tryParse(year.text.trim());
    if (year.text.trim().isNotEmpty && vehicleYear == null) {
      _snack('El año del vehículo no es válido.');
      return;
    }
    setState(() => saving = true);
    try {
      final result = await supabase.rpc(
        'update_my_driver_vehicle_for_review',
        params: {
          'p_vehicle_type': vehicleType,
          'p_vehicle_brand': brand.text.trim(),
          'p_vehicle_model': model.text.trim(),
          'p_vehicle_color': color.text.trim(),
          'p_vehicle_plate': plate.text.trim(),
          'p_vehicle_year': vehicleYear,
          'p_vehicle_photo_paths': vehiclePhotoPaths,
        },
      );
      if (!mounted) return;
      setState(() => approval = 'pending');
      Navigator.pop(context, result);
    } catch (e) {
      _snack(
        ExpressRuntimeChannel.userSafeError(
          e,
          fallback: 'No se pudieron guardar los datos del vehículo.',
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _saveFocusedDocuments() async {
    final extra = requirements.where((row) => !_identityRequirement(row)).toList();
    for (final requirement in extra) {
      if (requirement['required'] != true) continue;
      final id = requirement['id']?.toString();
      if (id == null) continue;
      final draft = _documents[id] ?? _DocumentDraft(id);
      final label = _text(requirement['label'], 'Documento');
      if (requirement['require_number'] == true &&
          draft.number.text.trim().isEmpty) {
        _snack('Completa el número de ' + label + '.');
        return;
      }
      if (requirement['require_front'] == true &&
          draft.frontPath?.isNotEmpty != true) {
        _snack('Sube el frente de ' + label + '.');
        return;
      }
      if (requirement['require_back'] == true &&
          draft.backPath?.isNotEmpty != true) {
        _snack('Sube el reverso de ' + label + '.');
        return;
      }
      if (requirement['require_selfie'] == true &&
          draft.selfiePath?.isNotEmpty != true) {
        _snack('Toma la selfie solicitada para ' + label + '.');
        return;
      }
    }

    final docs = <Map<String, dynamic>>[];
    for (final requirement in extra) {
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
        'update_my_driver_documents_for_review',
        params: {'p_documents': docs},
      );
      if (!mounted) return;
      setState(() => approval = 'pending');
      Navigator.pop(context, result);
    } catch (e) {
      _snack(
        ExpressRuntimeChannel.userSafeError(
          e,
          fallback: 'No se pudieron guardar los documentos.',
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _focusedTitle() {
    switch (widget.focusSection) {
      case 'location':
        return 'País y zona';
      case 'identity':
        return 'Documento de identidad';
      case 'profile':
        return 'Foto de perfil';
      case 'vehicle':
        return 'Datos del vehículo';
      case 'documents':
        return 'Documentos adicionales';
      default:
        return 'Vehículo y documentos';
    }
  }

  Widget _focusedContent() {
    switch (widget.focusSection) {
      case 'location':
        return _focusedLocationStep();
      case 'identity':
        return _focusedIdentityStep();
      case 'profile':
        return _focusedProfilePhotoStep();
      case 'vehicle':
        return _vehicleStep();
      case 'documents':
        return _focusedDocumentsStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget? _focusedFooter() {
    VoidCallback? action;
    String label = 'Guardar';
    switch (widget.focusSection) {
      case 'location':
        action = _saveFocusedLocation;
        label = 'Guardar y enviar a revisión';
        break;
      case 'identity':
        return null;
      case 'profile':
        if (!ExpressRuntimeChannel.previewMode && countryCode == 'BO') {
          return null;
        }
        action = _saveFocusedProfilePhoto;
        label = 'Guardar foto';
        break;
      case 'vehicle':
        action = _saveFocusedVehicle;
        label = 'Guardar vehículo';
        break;
      case 'documents':
        action = _saveFocusedDocuments;
        label = 'Guardar documentos';
        break;
      default:
        return null;
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE4E7EC))),
        ),
        child: FilledButton.icon(
          onPressed: saving ? null : action,
          icon: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded),
          label: Text(label),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: const Color(0xFF0B57D0),
          ),
        ),
      ),
    );
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

    if (_focusedEdit) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F9FC),
        appBar: AppBar(
          title: Text(_focusedTitle()),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _focusedContent(),
          ],
        ),
        bottomNavigationBar: _focusedFooter(),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: Text(
          widget.editExisting ? 'Vehículo y documentos' : 'Registro de conductor',
        ),
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


class DriverVehicleDocumentsPage extends StatefulWidget {
  final ExpressService service;

  const DriverVehicleDocumentsPage({
    super.key,
    required this.service,
  });

  @override
  State<DriverVehicleDocumentsPage> createState() =>
      _DriverVehicleDocumentsPageState();
}

class _DriverVehicleDocumentsPageState
    extends State<DriverVehicleDocumentsPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _asList(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
      : <Map<String, dynamic>>[];

  String _value(dynamic value) => value?.toString().trim() ?? '';

  Future<Map<String, dynamic>> _load() async {
    final state = _asMap(await supabase.rpc('my_driver_onboarding_state'));
    final profile = _asMap(state['profile']);
    final countryCode = _value(profile['country_code']);
    final zoneId = _value(profile['zone_id']);

    Map<String, dynamic> catalog = <String, dynamic>{};
    try {
      catalog = _asMap(
        await supabase.rpc(
          'driver_onboarding_catalog',
          params: {
            'p_country_code':
                countryCode.isEmpty ? null : countryCode.toUpperCase(),
            'p_zone_id': zoneId.isEmpty ? null : zoneId,
            'p_lat': null,
            'p_lng': null,
          },
        ),
      );
    } catch (_) {}

    Map<String, dynamic> didit = <String, dynamic>{};
    String profilePhotoPath = _value(profile['profile_photo_path']);
    try {
      final response = await supabase.functions.invoke(
        ExpressRuntimeChannel.previewMode
            ? 'didit-identity'
            : 'didit-identity-prod',
        body: const {'action': 'state'},
      );
      final data = _asMap(response.data);
      if (data['ok'] == true) {
        didit = _asMap(data['verification']);
        final diditPhoto = _value(data['profile_photo_path']);
        if (diditPhoto.isNotEmpty) profilePhotoPath = diditPhoto;
      }
    } catch (_) {}

    return <String, dynamic>{
      'state': state,
      'catalog': catalog,
      'didit': didit,
      'profile_photo_path': profilePhotoPath,
    };
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _openSection(String section, {int step = 0}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverSetupPage(
          service: widget.service,
          editExisting: true,
          initialStep: step,
          focusSection: section,
        ),
      ),
    );
    if (mounted) _reload();
  }

  bool _isIdentityRequirement(Map<String, dynamic> requirement) {
    final code = _value(requirement['code']).toLowerCase();
    final label = _value(requirement['label']).toLowerCase();
    const identityTokens = <String>[
      'identity',
      'national_id',
      'id_card',
      'carnet',
      'cedula',
      'cédula',
      'documento de identidad',
    ];
    return identityTokens.any(
      (token) => code.contains(token) || label.contains(token),
    );
  }

  bool _documentComplete(
    Map<String, dynamic> requirement,
    Map<String, dynamic>? document,
  ) {
    if (document == null) return false;
    if (requirement['require_number'] == true &&
        _value(document['document_number']).isEmpty) {
      return false;
    }
    if (requirement['require_front'] == true &&
        _value(document['front_object_path']).isEmpty) {
      return false;
    }
    if (requirement['require_back'] == true &&
        _value(document['back_object_path']).isEmpty) {
      return false;
    }
    if (requirement['require_selfie'] == true &&
        _value(document['selfie_object_path']).isEmpty) {
      return false;
    }
    return true;
  }

  String _identityStatus(Map<String, dynamic> didit) {
    switch (_value(didit['status']).toLowerCase()) {
      case 'verified':
        return 'Verificado';
      case 'rejected':
        return 'Rechazado · vuelve a verificar tu identidad';
      case 'review':
        return 'En revisión';
      case 'processing':
        return 'Procesando';
      case 'pending':
        return 'Pendiente de completar';
      default:
        return 'Aún no verificado';
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('verificado') ||
        normalized.contains('completo') ||
        normalized.contains('registrado') ||
        normalized.contains('registrada')) {
      return const Color(0xFF067647);
    }
    if (normalized.contains('rechaz')) return const Color(0xFFB42318);
    if (normalized.contains('revisión') ||
        normalized.contains('procesando') ||
        normalized.contains('pendiente')) {
      return const Color(0xFFB54708);
    }
    return Theme.of(context).colorScheme.primary;
  }

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String status,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    final color = _statusColor(context, status);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .12),
              foregroundColor: color,
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onTap,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Vehículo y documentos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 42),
                    const SizedBox(height: 10),
                    const Text(
                      'No pudimos cargar tus datos de conductor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data ?? const <String, dynamic>{};
          final state = _asMap(data['state']);
          final profile = _asMap(state['profile']);
          final vehicle = _asMap(state['vehicle']);
          final didit = _asMap(data['didit']);
          final catalog = _asMap(data['catalog']);
          final requirements = _asList(catalog['document_requirements']);
          final documents = _asList(state['documents']);
          final profilePhotoPath = _value(data['profile_photo_path']);

          final identityStatus = _identityStatus(didit);
          final identityVerified =
              _value(didit['status']).toLowerCase() == 'verified';

          final vehicleBrand = _value(vehicle['brand']);
          final vehicleModel = _value(vehicle['model']);
          final vehiclePlate = _value(vehicle['plate']);
          final vehicleColor = _value(vehicle['color']);
          final vehicleYear = _value(vehicle['year']);
          final hasVehicle = vehicleBrand.isNotEmpty ||
              vehicleModel.isNotEmpty ||
              vehiclePlate.isNotEmpty;
          final vehicleComplete = vehicleBrand.isNotEmpty &&
              vehicleModel.isNotEmpty &&
              vehiclePlate.isNotEmpty;
          final vehicleDescription = hasVehicle
              ? <String>[
                  [vehicleBrand, vehicleModel]
                      .where((e) => e.isNotEmpty)
                      .join(' '),
                  if (vehiclePlate.isNotEmpty) 'Placa $vehiclePlate',
                  if (vehicleColor.isNotEmpty) vehicleColor,
                  if (vehicleYear.isNotEmpty) vehicleYear,
                ].where((e) => e.isNotEmpty).join(' · ')
              : 'No tenemos datos de tu vehículo. Rellénalo ahora.';

          final extraRequirements = requirements
              .where((row) => !_isIdentityRequirement(row))
              .toList();
          final documentsByRequirement = <String, Map<String, dynamic>>{
            for (final row in documents)
              if (_value(row['requirement_id']).isNotEmpty)
                _value(row['requirement_id']): row,
          };
          final requiredExtra = extraRequirements
              .where((row) => row['required'] == true)
              .toList();
          final completedExtra = requiredExtra
              .where(
                (row) => _documentComplete(
                  row,
                  documentsByRequirement[_value(row['id'])],
                ),
              )
              .length;

          final zoneLabel = [
            _value(profile['city']),
            _value(profile['country_code']).toUpperCase(),
          ].where((e) => e.isNotEmpty).join(' · ');

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              children: [
                Text(
                  'Tus datos de conductor',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  zoneLabel.isEmpty
                      ? 'Aquí puedes revisar lo que ya está registrado y completar solo lo que falta.'
                      : '$zoneLabel · Revisa lo registrado y completa solo lo que falta.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _summaryCard(
                  icon: Icons.public_rounded,
                  title: 'País y zona',
                  subtitle: zoneLabel.isEmpty
                      ? 'Selecciona el país y la zona donde trabajarás como conductor.'
                      : 'Actualmente: ' + zoneLabel + '.',
                  status:
                      _value(profile['approval_status']).toLowerCase() == 'pending'
                          ? 'Los cambios de zona requieren revisión'
                          : 'Zona registrada',
                  actionLabel: 'Cambiar',
                  onTap: () => _openSection('location', step: 0),
                ),
                _summaryCard(
                  icon: Icons.badge_outlined,
                  title: 'Documento de identidad',
                  subtitle: identityVerified
                      ? 'Tu identidad, prueba de vida y coincidencia facial ya fueron verificadas.'
                      : 'Verifica tu documento de identidad, prueba de vida y coincidencia facial.',
                  status: identityStatus,
                  actionLabel: identityVerified ? 'Revisar' : 'Verificar',
                  onTap: () => _openSection('identity', step: 1),
                ),
                _summaryCard(
                  icon: Icons.account_circle_outlined,
                  title: 'Foto de perfil',
                  subtitle: profilePhotoPath.isNotEmpty
                      ? 'Ya tienes una foto de perfil registrada para tu cuenta de conductor.'
                      : 'Todavía no tenemos una foto de perfil válida para tu cuenta de conductor.',
                  status: profilePhotoPath.isNotEmpty
                      ? 'Foto registrada'
                      : 'Falta completar',
                  actionLabel:
                      profilePhotoPath.isNotEmpty ? 'Actualizar' : 'Completar',
                  onTap: () => _openSection('profile', step: 1),
                ),
                _summaryCard(
                  icon: Icons.directions_car_outlined,
                  title: 'Datos del vehículo',
                  subtitle: vehicleDescription,
                  status: vehicleComplete
                      ? 'Vehículo registrado'
                      : hasVehicle
                          ? 'Faltan datos del vehículo'
                          : 'Sin vehículo registrado',
                  actionLabel: hasVehicle ? 'Editar' : 'Rellenar ahora',
                  onTap: () => _openSection('vehicle', step: 2),
                ),
                if (extraRequirements.isNotEmpty)
                  _summaryCard(
                    icon: Icons.description_outlined,
                    title: 'Documentos adicionales',
                    subtitle: requiredExtra.isEmpty
                        ? 'Tu ciudad tiene documentos opcionales que puedes revisar.'
                        : completedExtra.toString() +
                            ' de ' +
                            requiredExtra.length.toString() +
                            ' requisito(s) obligatorio(s) completos.',
                    status: requiredExtra.isEmpty ||
                            completedExtra == requiredExtra.length
                        ? 'Documentos completos'
                        : 'Faltan documentos',
                    actionLabel: 'Revisar',
                    onTap: () => _openSection('documents', step: 3),
                  ),
              ],
            ),
          );
        },
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

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connected_center.dart';
import 'driver_manual_identity_capture.dart';
import 'driver_kyc_correction_page.dart';
import 'driver_registration_status_watcher.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'express_motion.dart';
import 'location_service.dart';
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
  late final DriverRegistrationStatusWatcher _approvalWatcher;
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
  String approval = 'pending';
  bool registrationAllowed = false;
  String? availabilityMessage;
  double? detectedLatitude;
  double? detectedLongitude;
  bool manualLocationSelected = false;

  bool get _manualIdentity => true;

  bool get _vehicleStepEnabled => services.any((service) {
        final type = _text(service['vehicle_type']).toLowerCase();
        return type.isNotEmpty && type != 'none';
      });

  bool get _documentsStepEnabled => requirements.isNotEmpty;

  bool get _licenseRequirementEnabled => requirements.any(
        (requirement) =>
            _text(requirement['code']).toLowerCase() == 'driver_license',
      );

  List<String> get _flowSteps => <String>[
        'location',
        'profile',
        if (_vehicleStepEnabled) 'vehicle',
        if (_documentsStepEnabled) 'documents',
        'review',
      ];

  String get _currentFlowStep {
    final flow = _flowSteps;
    if (flow.isEmpty) return 'review';
    final index = step.clamp(0, flow.length - 1).toInt();
    return flow[index];
  }

  String? countryCode;
  String? zoneId;
  String? profilePhotoPath;
  final List<String> vehiclePhotoPaths = <String>[];
  final Set<String> selectedServices = <String>{};
  String vehicleType = '';

  List<Map<String, dynamic>> countries = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> zones = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> services = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> requirements = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    step = widget.initialStep.clamp(0, 4).toInt();
    _approvalWatcher = DriverRegistrationStatusWatcher(
      userId: widget.service.userId,
      onChanged: _checkApprovalWithoutOverwritingForm,
    )..start();
    _load();
  }

  /// Keep partially entered form fields intact when the administrator
  /// approves, rejects or reopens registration on another device.
  Future<void> _checkApprovalWithoutOverwritingForm() async {
    if (!mounted || saving) return;
    try {
      final row = await supabase
          .from('driver_profiles')
          .select('approval_status')
          .eq('id', widget.service.userId)
          .maybeSingle();
      if (!mounted || row == null) return;
      final next = _text(row['approval_status'], 'pending');
      if (next == approval) return;
      setState(() => approval = next);
      if (next == 'approved' && !widget.editExisting) {
        Navigator.of(context).pop(<String, dynamic>{
          'approval_status': 'approved',
        });
      }
    } catch (_) {
      // A transient network failure must not remove the user's form edits.
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
      vehicleType = _text(vehicle['vehicle_type']);
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

      if (!widget.editExisting) {
        await _detectLocation(silent: true);
      } else if (countryCode != null || zoneId != null) {
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
        draft.status = _text(row['status'], 'not_started').toLowerCase();
        draft.reviewParts = _map(row['review_parts']);
        final expiration = DateTime.tryParse(_text(row['expires_at']));
        // Fecha final exclusiva almacenada en la zona horaria del documento.
        draft.expiryDate = expiration?.toLocal().subtract(
          const Duration(seconds: 1),
        );
        draft.rejectionReason = _text(
          row['rejection_reason'] ?? row['notes'],
        );
        draft.dirty = false;
      }

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
    var nextRequirements = _list(data['document_requirements']);
    final selectedCountry = _text(
      selectedZone['country_code'] ?? country ?? countryCode,
    ).toUpperCase();
    if (selectedCountry.isNotEmpty) {
      // The legacy provider-specific catalog hides identity requirements.
      final raw=await supabase.from('driver_document_requirements')
          .select().eq('active',true);
      final all=_list(raw);
      final ids=nextRequirements.map((r)=>r['id']?.toString()).toSet();
      nextRequirements=[
        ...nextRequirements,
        ...all.where((row) {
          final code=_text(row['code']).toLowerCase();
          final region=_text(row['country_code']).toUpperCase();
          final rowZone=_text(row['zone_id']);
          return <String>{'identity_card','national_id','id_card',
              'identity','carnet','cedula','cédula'}.contains(code) &&
            (region.isEmpty || region==selectedCountry) &&
            (rowZone.isEmpty ||
              rowZone==(zone ?? selectedZone['id']?.toString())) &&
            !ids.contains(row['id']?.toString());
        }),
      ];
    }
    final nextRegistrationAllowed = data['registration_allowed'] == true;
    final nextAvailabilityMessage = data['availability_message']?.toString();

    if (!mounted) return;
    setState(() {
      if (nextCountries.isNotEmpty) countries = nextCountries;
      zones = nextZones;
      services = _list(data['services']);
      requirements = nextRequirements;
      registrationAllowed = nextRegistrationAllowed;
      availabilityMessage = nextAvailabilityMessage;

      final requestedCountry = country?.trim().toUpperCase();
      final countryExists = requestedCountry != null &&
          nextCountries.any(
            (row) => row['code']?.toString().toUpperCase() == requestedCountry,
          );
      if (countryExists) {
        countryCode = requestedCountry;
      } else if (!widget.editExisting && selectedZone.isEmpty) {
        countryCode = null;
      }

      if (selectedZone.isNotEmpty) {
        zoneId = selectedZone['id']?.toString();
        countryCode = selectedZone['country_code']?.toString();
      } else if (zone == null && suggested != null && suggested.isNotEmpty) {
        zoneId = suggested;
      } else if (!widget.editExisting) {
        zoneId = null;
      }

      _syncDocumentDrafts();
      _syncServiceSelection();
      final maxStep = _flowSteps.length - 1;
      if (step > maxStep) step = maxStep;
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
    }
  }

  Future<void> _detectLocation({bool silent = false}) async {
    if (detecting) return;
    setState(() => detecting = true);

    try {
      const locationService = ExpressLocationService();
      Position? position;

      if (silent) {
        // Onboarding can be opened repeatedly while the driver is completing
        // data. Reuse the device cache and never pop a permission dialog just
        // because this screen was rebuilt.
        position = await locationService.cachedPosition(
          maxAge: ExpressLocationService.persistentFallbackMaxAge,
        );

        if (position == null) {
          final permission = await Geolocator.checkPermission();
          final granted = permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse;
          final enabled = await Geolocator.isLocationServiceEnabled();
          if (granted && enabled) {
            position = await locationService.passivePosition(
              cacheMaxAge: const Duration(minutes: 15),
            );
          }
        }

        if (position == null) {
          if (countryCode != null || zoneId != null) {
            await _refreshCatalog(country: countryCode, zone: zoneId);
          }
          return;
        }
      } else {
        // Explicit "detect my location" is the only onboarding action allowed
        // to request permission. It still uses the low-cost location tier.
        position = await locationService.passivePosition(
          cacheMaxAge: const Duration(minutes: 2),
        );
        if (position == null) {
          _snack(
            'Activa la ubicación para detectar tu ciudad o selecciónala manualmente.',
          );
          return;
        }
      }

      detectedLatitude = position.latitude;
      detectedLongitude = position.longitude;
      manualLocationSelected = false;

      // The backend already owns the coverage polygons and country/zone
      // mapping. Let it resolve the point directly instead of making a second
      // reverse-geocoding HTTP request from the phone.
      await _refreshCatalog(
        lat: position.latitude,
        lng: position.longitude,
      );

      if (!silent && !registrationAllowed) {
        _snack(
          availabilityMessage ??
              'Express todavía no está disponible para conductores en esta zona.',
        );
      }
    } catch (_) {
      if (!silent) {
        _snack(
          'No se pudo validar tu ubicación. Puedes seleccionar país y ciudad manualmente.',
        );
      }
    } finally {
      if (mounted) setState(() => detecting = false);
    }
  }

  Future<void> _selectCountry(String? value) async {
    if (value == null) return;
    setState(() {
      countryCode = value;
      zoneId = null;
      manualLocationSelected = true;
      detectedLatitude = null;
      detectedLongitude = null;
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
      manualLocationSelected = true;
      detectedLatitude = null;
      detectedLongitude = null;
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
        // El servicio no elige automáticamente el vehículo. El conductor
        // debe confirmarlo explícitamente en su formulario.
        if (vehicleType.isNotEmpty && vehicleType != type) {
          vehicleType = '';
        }
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
        draft.dirty = true;
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

  bool _flowStepValid(String flowStep, {bool showMessage = true}) {
    String? message;
    if (flowStep == 'location') {
      if (!widget.editExisting && !registrationAllowed) {
        message = availabilityMessage ??
            'Express todavía no está disponible para conductores en esta zona.';
      } else if (countryCode == null || zoneId == null) {
        message = 'No pudimos validar una zona activa de Express.';
      } else if (selectedServices.isEmpty) {
        message = 'Selecciona al menos un servicio activo de la ciudad.';
      }
    } else if (flowStep == 'profile') {
      if (profilePhotoPath == null || profilePhotoPath!.isEmpty) {
        message = 'Carga tu fotografía facial.';
      }
    } else if (flowStep == 'vehicle' && _vehicleStepEnabled) {
      if (vehicleType.isEmpty) {
        message = 'Selecciona el tipo de vehículo que vas a utilizar.';
      } else if (selectedServices.isEmpty) {
        message = 'Selecciona al menos un servicio compatible con tu vehículo.';
      } else if (selectedServices.any((key) => !services.any(
          (service) => service['service_key']?.toString() == key &&
              _text(service['vehicle_type']).toLowerCase() == vehicleType
      ))) {
        message = 'Los servicios seleccionados no coinciden con tu vehículo.';
      } else if (brand.text.trim().isEmpty ||
          model.text.trim().isEmpty ||
          plate.text.trim().isEmpty) {
        message = 'Completa marca, modelo y placa.';
      } else if (vehiclePhotoPaths.isEmpty) {
        message = 'Sube al menos una foto del vehículo.';
      }
    } else if (flowStep == 'documents' && _documentsStepEnabled) {
      for (final requirement in requirements) {
        if (requirement['required'] != true) continue;
        final id = requirement['id']?.toString();
        if (id == null) continue;
        final draft = _documents[id] ?? _DocumentDraft(id);
        final label = _text(requirement['label'], 'Documento');
        if (requirement['require_number'] == true &&
            draft.number.text.trim().isEmpty) {
          message = 'Completa el número de ' + label + '.';
          break;
        }
        if (requirement['require_front'] == true &&
            (draft.frontPath?.isNotEmpty != true)) {
          message = 'Sube el frente de ' + label + '.';
          break;
        }
        if (requirement['require_back'] == true &&
            (draft.backPath?.isNotEmpty != true)) {
          message = 'Sube el reverso de ' + label + '.';
          break;
        }
        if (requirement['require_selfie'] == true &&
            (draft.selfiePath?.isNotEmpty != true)) {
          message = 'Toma la selfie solicitada para ' + label + '.';
          break;
        }
        if (_needsExpiry(requirement) &&
            draft.expiryDate == null && !draft.approved) {
          message = 'Indica el vencimiento de ' + label + '.';
          break;
        }
        if (draft.expiryDate != null) {
          final d=draft.expiryDate!;
          final now=DateTime.now();
          if (DateTime(d.year,d.month,d.day).isBefore(
             DateTime(now.year,now.month,now.day))) {
            message = 'El documento ' + label + ' está vencido.';
            break;
          }
        }
      }
    }

    if (message != null && showMessage) _snack(message);
    return message == null;
  }

  Future<void> _continue() async {
    final flow = _flowSteps;
    if (flow.isEmpty) return;
    final current = step.clamp(0, flow.length - 1).toInt();
    if (!_flowStepValid(flow[current])) return;
    if (current < flow.length - 1) {
      setState(() => step = current + 1);
    }
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
    if (!widget.editExisting && !registrationAllowed) {
      _snack(
        availabilityMessage ??
            'Selecciona una ciudad activa de Express para continuar.',
      );
      setState(() => step = 0);
      return;
    }
    final flow = _flowSteps;
    for (var i = 0; i < flow.length; i++) {
      final flowStep = flow[i];
      if (flowStep == 'review') continue;
      if (!_flowStepValid(flowStep)) {
        setState(() => step = i);
        return;
      }
    }

    final vehicleYear =
        year.text.trim().isEmpty ? null : int.tryParse(year.text.trim());
    if (_vehicleStepEnabled &&
        year.text.trim().isNotEmpty &&
        vehicleYear == null) {
      _snack('El año del vehículo no es válido.');
      final vehicleStep = flow.indexOf('vehicle');
      if (vehicleStep >= 0) setState(() => step = vehicleStep);
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
        'expires_at': draft.expiryDate == null ? null
            : '${draft.expiryDate!.year.toString().padLeft(4, '0')}-'
              '${draft.expiryDate!.month.toString().padLeft(2, '0')}-'
              '${draft.expiryDate!.day.toString().padLeft(2, '0')}',
      });
    }

    setState(() => saving = true);
    try {
      final result = await supabase.rpc(
        widget.editExisting
            ? 'submit_driver_onboarding'
            : 'submit_driver_onboarding_v2',
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
          if (!widget.editExisting)
            'p_lat': manualLocationSelected ? null : detectedLatitude,
          if (!widget.editExisting)
            'p_lng': manualLocationSelected ? null : detectedLongitude,
        },
      );
      if (!mounted) return;
      setState(() => approval = 'pending');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.verified_user_outlined, size: 42),
          title: const Text('Tu documento ha sido cargado exitosamente'),
          content: const Text(
            'Un administrador revisará tu información. '
            'La revisión puede tardar 24 horas o más.',
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark
        ? tone.withValues(alpha: .12)
        : approved
            ? const Color(0xFFECFDF3)
            : const Color(0xFFFFFAEB);
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
          text: widget.editExisting
              ? 'Usa tu ubicación para confirmar la zona operativa. Si no está disponible, puedes elegir país y ciudad manualmente.'
              : 'Express intentará detectar automáticamente tu ciudad. Si el GPS no está disponible, selecciona país y ciudad manualmente para continuar.',
          action: TextButton.icon(
            onPressed: detecting ? null : () => _detectLocation(),
            icon: detecting
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.gps_fixed_rounded),
            label: Text(detecting ? 'Detectando...' : 'Detectar de nuevo'),
          ),
        ),
        const SizedBox(height: 14),
        if (!widget.editExisting &&
            zoneId != null &&
            !registrationAllowed) ...[
          _HintCard(
            icon: Icons.location_off_rounded,
            title: 'Zona todavía no disponible',
            text: availabilityMessage ??
                'Express todavía no está disponible para conductores en esta zona.',
          ),
          const SizedBox(height: 12),
        ],
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
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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

  Future<void> _captureManualIdentity() async {
    if (!_manualIdentity || saving) return;
    final identity = requirements.where((row) =>
        _identityRequirement(row)).toList();
    if (identity.isEmpty) {
      _snack('No encontramos el requisito de identidad para tu zona.');
      return;
    }
    final id = identity.first['id']?.toString();
    if (id == null || id.isEmpty) return;
    final draft = _documents.putIfAbsent(id, () => _DocumentDraft(id));
    final result = await Navigator.of(context)
        .push<DriverManualIdentityCaptureResult>(MaterialPageRoute(
      builder: (_) => DriverManualIdentityCapturePage(
        countryName: countryCode == null ? 'No seleccionado' : _countryName(countryCode!),
        initialDocumentNumber: draft.number.text,
        initialFrontPath: draft.frontPath,
        initialBackPath: draft.backPath,
        initialSelfiePath: draft.selfiePath,
        uploadCameraPhoto: (slot) => _pickAndUpload(
          folder: 'documents/$id',
          slot: slot,
          source: ImageSource.camera,
        ),
      ),
    ));
    if (result == null || !mounted) return;
    setState(() {
      draft.number.text = result.documentNumber;
      draft.frontPath = result.frontPath;
      draft.backPath = result.backPath;
      draft.selfiePath = result.selfiePath;
      draft.dirty = true;
      profilePhotoPath = result.selfiePath;
    });

    // An isolated identity edit must persist immediately. The regular signup
    // wizard still submits all data together in _submit().
    if (widget.editExisting && widget.focusSection == 'identity') {
      setState(() => saving = true);
      try {
        await supabase.rpc('update_my_driver_documents_for_review', params: {
          'p_documents': [
            {
              'requirement_id': id,
              'document_type': _text(identity.first['code'], 'identity_card'),
              'document_number': result.documentNumber,
              'front_object_path': result.frontPath,
              'back_object_path': result.backPath,
              'selfie_object_path': result.selfiePath,
            }
          ],
        });
        // The existing database trigger mirrors the selfie into the driver's
        // profile and starts independent review; no duplicate upload needed.
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } catch (e) {
        if (mounted) {
          _snack(ExpressRuntimeChannel.userSafeError(
            e,
            fallback: 'No se pudo enviar el carné a revisión. Intenta nuevamente.',
          ));
        }
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
  }

  Widget _profileStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _UploadTile(
        icon: Icons.badge_outlined,
        title: 'Carga tu documento',
        subtitle: 'Frente, reverso y una fotografía facial.',
        complete: profilePhotoPath?.isNotEmpty == true,
        onTap: saving ? null : _captureManualIdentity,
      ),
      const SizedBox(height: 12),
      if (countryCode != null && zoneId != null)
        _InfoLine(icon: Icons.pin_drop_outlined,
          text: '${_countryName(countryCode!)} · ${_zoneName(zoneId!)}'),
    ],
  );
  Widget _focusedIdentityStep() => _profileStep();

  // Profile photographs have their own upload and save flow. They must not
  // reopen the three-step identity/carnet capture.
  Widget _focusedProfilePhotoStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UploadTile(
            icon: Icons.account_circle_outlined,
            title: 'Foto de perfil',
            subtitle: 'Sube solo tu fotografía; no es necesario repetir el carné.',
            complete: profilePhotoPath?.isNotEmpty == true,
            onTap: saving ? null : _pickProfilePhoto,
          ),
          const SizedBox(height: 12),
          const _HintCard(
            icon: Icons.info_outline_rounded,
            title: 'Revisión independiente',
            text: 'La foto de perfil se revisa por separado. El frente y reverso '
                'de tu documento conservan sus aprobaciones.',
          ),
        ],
      );

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

    final types = services
        .map((service) => _text(service['vehicle_type']).toLowerCase())
        .where((type) => type.isNotEmpty && type != 'none')
        .toSet()
        .toList()..sort();
    if (vehicleType.isNotEmpty && !types.contains(vehicleType)) {
      types.add(vehicleType);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Qué vehículo vas a ocupar?',
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('Selecciona tu vehículo. Solo recibirás servicios compatibles con tu zona.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final type in types)
              ChoiceChip(
                avatar: Icon(_vehicleIcon(type), size: 18),
                label: Text(switch(type) {
                  'motorcycle' => 'Moto',
                  'car' => 'Automóvil',
                  'suv' => 'SUV',
                  'van' => 'Van',
                  'bicycle' => 'Bicicleta',
                  _ => type,
                }),
                selected: vehicleType == type,
                onSelected: saving ? null : (value) {
                  if (!value) return;
                  setState(() {
                    vehicleType = type;
                    selectedServices.removeWhere((key) => !services.any(
                      (service) => service['service_key']?.toString() == key &&
                          _text(service['vehicle_type']).toLowerCase() == type,
                    ));
                    final matching = services.where((service) =>
                      _text(service['vehicle_type']).toLowerCase() == type).toList();
                    if (selectedServices.isEmpty && matching.length == 1) {
                      selectedServices.add(matching.first['service_key'].toString());
                    }
                  });
                },
              ),
          ],
        ),
        if (vehicleType.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Servicios que realizarás con este vehículo',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 7),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final service in services.where((row) =>
                _text(row['vehicle_type']).toLowerCase() == vehicleType))
              FilterChip(
                label: Text(_text(service['name'],
                    _text(service['service_key'], 'Servicio'))),
                selected: selectedServices.contains(
                    service['service_key']?.toString()),
                onSelected: saving ? null
                    : (selected) => _toggleService(service, selected),
              ),
          ]),
        ],
        if (selectedNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          _HintCard(
            icon: _vehicleIcon(vehicleType),
            title: 'Vehículo para ' + selectedNames,
            text: 'Estos servicios están habilitados en tu zona.',
          ),
        ],
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

  bool _needsExpiry(Map<String,dynamic> requirement) {
    if (requirement['expiration_required'] == true) return true;
    final code = _text(requirement['code']).toLowerCase();
    return code == 'driver_license' || code == 'soat'
        || code.contains('insurance') || code.contains('seguro')
        || code.contains('technical_inspection')
        || code.contains('revision_tecnica');
  }

  bool _mayRenew(_DocumentDraft draft, Map<String, dynamic> requirement) {
    if (!draft.approved) return true;
    final expires = draft.expiryDate;
    if (expires == null) return false; // Legacy approved file stays locked.
    final now = DateTime.now();
    final remaining = DateTime(expires.year, expires.month, expires.day)
        .difference(DateTime(now.year, now.month, now.day)).inDays;
    return remaining <= 30;
  }

  Future<void> _chooseDocumentExpiry(_DocumentDraft draft) async {
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final initial = draft.expiryDate != null &&
        !draft.expiryDate!.isBefore(first)
      ? draft.expiryDate! : first;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(today.year + 15, today.month, today.day),
      helpText: 'Fecha de vencimiento del documento',
    );
    if (selected == null || !mounted) return;
    setState(() {
      draft.expiryDate = selected;
      draft.dirty = true;
    });
  }

  Widget _documentsStep() {
    if (requirements.isEmpty) {
      return const _HintCard(
        icon: Icons.description_outlined,
        title: 'Sin documentos configurados',
        text: 'El administrador todavía no configuró documentos obligatorios para esta ciudad.',
      );
    }

    String reviewLabel(_DocumentDraft draft) {
      if (draft.approved) return 'Aprobado';
      if (draft.rejected) return 'Rechazado';
      if (draft.pending) return 'En revisión';
      return 'Falta enviar';
    }

    Color reviewColor(_DocumentDraft draft) {
      final scheme = Theme.of(context).colorScheme;
      if (draft.approved) return scheme.primary;
      if (draft.rejected) return scheme.error;
      if (draft.pending) return scheme.tertiary;
      return scheme.onSurfaceVariant;
    }

    return Column(
      children: [
        ...requirements.map((requirement) {
          final id = requirement['id']?.toString() ?? '';
          final draft = _documents.putIfAbsent(id, () => _DocumentDraft(id));
          final required = requirement['required'] == true;
          final locked = draft.approved && !_mayRenew(draft, requirement);
          final tone = reviewColor(draft);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: draft.rejected
                      ? Theme.of(context).colorScheme.error.withValues(alpha: .55)
                      : locked
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: .5)
                          : Theme.of(context).dividerColor.withValues(alpha: .55),
                ),
                color: locked
                    ? Theme.of(context).colorScheme.primaryContainer
                        .withValues(alpha: .28)
                    : draft.rejected
                        ? Theme.of(context).colorScheme.errorContainer
                            .withValues(alpha: .25)
                        : Theme.of(context).colorScheme.surface,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: tone.withValues(alpha: .12),
                        child: Icon(
                          locked
                              ? Icons.verified_rounded
                              : draft.rejected
                                  ? Icons.error_outline_rounded
                                  : Icons.badge_outlined,
                          color: tone,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _text(requirement['label'], 'Documento'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (_text(requirement['description']).isNotEmpty)
                              Text(
                                _text(requirement['description']),
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (required)
                        const Chip(label: Text('Obligatorio')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: tone),
                      const SizedBox(width: 6),
                      Text(
                        reviewLabel(draft),
                        style: TextStyle(
                          color: tone,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  if (draft.rejected && draft.rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Motivo: ' + draft.rejectionReason,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  if (locked) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Este documento ya fue aprobado. No necesitas volver a cargarlo.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (requirement['require_number'] == true) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: draft.number,
                      readOnly: locked,
                      onChanged: locked
                          ? null
                          : (_) {
                              draft.dirty = true;
                            },
                      decoration: InputDecoration(
                        labelText: 'Número del documento',
                        helperText: locked ? 'Aprobado · solo lectura' : null,
                      ),
                    ),
                  ],
                  if (_needsExpiry(requirement) ||
                      draft.expiryDate != null) ...[
                    const SizedBox(height: 12),
                    Builder(builder: (context) {
                      final expiry = draft.expiryDate;
                      final now = DateTime.now();
                      final days = expiry == null ? null
                          : DateTime(expiry.year,expiry.month,expiry.day)
                          .difference(DateTime(now.year,now.month,now.day))
                          .inDays;
                      final warning = days == null
                          ? Theme.of(context).colorScheme.primary
                          : days < 0 ? const Color(0xFFB42318)
                          : days <= 30 ? const Color(0xFFB54708)
                          : const Color(0xFF067647);
                      return OutlinedButton.icon(
                        onPressed: saving || locked ? null
                            : () => _chooseDocumentExpiry(draft),
                        icon: Icon(days != null && days < 0
                            ? Icons.error_rounded
                            : Icons.event_available_outlined),
                        label: Text(expiry == null
                            ? 'Seleccionar vencimiento'
                            : days! < 0
                              ? 'Vencido: ${expiry.day}/${expiry.month}/${expiry.year}'
                              : days <= 30
                                ? 'Vence en $days días · ${expiry.day}/${expiry.month}/${expiry.year}'
                                : 'Vence: ${expiry.day}/${expiry.month}/${expiry.year}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: warning,
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (requirement['require_front'] == true)
                        _DocButton(
                          label: 'Frente',
                          status: draft.slotStatus('front'),
                          icon: Icons.credit_card_rounded,
                          onPressed: saving || locked || draft.slotStatus('front') == 'approved'
                              ? null
                              : () => _pickDocument(requirement, 'front'),
                        ),
                      if (requirement['require_back'] == true)
                        _DocButton(
                          label: 'Reverso',
                          status: draft.slotStatus('back'),
                          icon: Icons.flip_to_back_rounded,
                          onPressed: saving || locked || draft.slotStatus('back') == 'approved'
                              ? null
                              : () => _pickDocument(requirement, 'back'),
                        ),
                      if (requirement['require_selfie'] == true)
                        _DocButton(
                          label: 'Selfie',
                          status: draft.slotStatus('selfie'),
                          icon: Icons.face_retouching_natural_rounded,
                          onPressed: saving || locked || draft.slotStatus('selfie') == 'approved'
                              ? null
                              : () => _pickDocument(requirement, 'selfie'),
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
          text:
              'Tu cuenta quedará pendiente hasta que un administrador revise los requisitos activos de tu ciudad.',
        ),
        const SizedBox(height: 14),
        _ReviewRow(
          'País',
          countryCode == null ? '—' : _countryName(countryCode!),
        ),
        _ReviewRow('Ciudad', zoneId == null ? '—' : _zoneName(zoneId!)),
        _ReviewRow('Servicios', serviceNames.isEmpty ? '—' : serviceNames),
        if (_licenseRequirementEnabled)
          _ReviewRow(
            'Licencia',
            _documentNumberForCode('driver_license').isEmpty
                ? '—'
                : _documentNumberForCode('driver_license'),
          ),
        if (_vehicleStepEnabled) ...[
          _ReviewRow(
            'Vehículo',
            (brand.text.trim() + ' ' + model.text.trim()).trim(),
          ),
          _ReviewRow(
            'Placa',
            plate.text.trim().isEmpty ? '—' : plate.text.trim(),
          ),
        ],
        if (_documentsStepEnabled)
          _ReviewRow(
            'Documentos',
            requirements.length.toString() + ' requisito(s)',
          ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: true,
          onChanged: null,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Confirmo que la información entregada es correcta.',
          ),
          subtitle: const Text(
            'La aprobación puede rechazarse si los datos no coinciden.',
          ),
        ),
      ],
    );
  }

  String _flowStepShortLabel(String flowStep) {
    switch (flowStep) {
      case 'location':
        return 'Zona';
      case 'profile':
        return 'Perfil';
      case 'vehicle':
        return 'Vehículo';
      case 'documents':
        return 'Documentos';
      default:
        return 'Revisión';
    }
  }

  Widget _flowMotionHeader(List<String> flowSteps, int safeStep) {
    final total = flowSteps.length;
    final progress = total == 0 ? 0.0 : (safeStep + 1) / total;
    final currentLabel = total == 0
        ? 'Preparando registro'
        : _flowStepShortLabel(flowSteps[safeStep]);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ExpressMotionSwap(
                  alignment: Alignment.centerLeft,
                  duration: ExpressMotion.fast,
                  incomingOffset: const Offset(.025, 0),
                  child: Text(
                    currentLabel,
                    key: ValueKey('driver-flow-label-' +
                        safeStep.toString() +
                        '-' +
                        currentLabel),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              Text(
                'Paso ' + (safeStep + 1).toString() + ' de ' + total.toString(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ExpressMotionProgress(
            value: progress,
            height: 7,
            color: const Color(0xFF0B57D0),
          ),
        ],
      ),
    );
  }

  Step _buildFlowStep(String flowStep, int index) {
    final completed = step > index;
    switch (flowStep) {
      case 'location':
        return Step(
          title: const Text('País, ciudad y servicios'),
          subtitle: const Text('GPS + disponibilidad local'),
          isActive: step >= index,
          state: completed ? StepState.complete : StepState.indexed,
          content: _locationStep(),
        );
      case 'profile':
        return Step(
          title: const Text('Perfil'),
          subtitle: const Text('Foto personal'),
          isActive: step >= index,
          state: completed ? StepState.complete : StepState.indexed,
          content: _profileStep(),
        );
      case 'vehicle':
        return Step(
          title: const Text('Vehículo'),
          subtitle: Text(
            vehicleType == 'motorcycle'
                ? 'Datos y fotografías de la moto'
                : 'Datos y fotografías',
          ),
          isActive: step >= index,
          state: completed ? StepState.complete : StepState.indexed,
          content: _vehicleStep(),
        );
      case 'documents':
        return Step(
          title: const Text('Documentos'),
          subtitle: const Text('Requisitos activos de tu ciudad'),
          isActive: step >= index,
          state: completed ? StepState.complete : StepState.indexed,
          content: _documentsStep(),
        );
      default:
        return Step(
          title: const Text('Revisar y enviar'),
          subtitle: const Text('Solicitud de aprobación'),
          isActive: step >= index,
          content: _reviewStep(),
        );
    }
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
    if (!_flowStepValid('vehicle')) return;
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
    final extra =
        requirements.where((row) => !_identityRequirement(row)).toList();
    final docs = <Map<String, dynamic>>[];

    for (final requirement in extra) {
      final id = requirement['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final draft = _documents[id] ?? _DocumentDraft(id);
      final label = _text(requirement['label'], 'Documento');

      // Approved documents are immutable from the driver's correction flow.
      // They remain valid while another document is being corrected.
      if (draft.approved && (!_mayRenew(draft,requirement) || !draft.dirty)) continue;

      if (draft.rejected && !draft.dirty) {
        _snack('Corrige únicamente $label. Los documentos aprobados no se vuelven a cargar.');
        return;
      }

      // A document already pending review does not need to be resubmitted
      // unless the driver actually changed it.
      if (draft.pending && !draft.dirty) continue;

      if (requirement['required'] == true) {
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
        if (_needsExpiry(requirement) &&
            draft.expiryDate == null) {
          _snack('Indica la fecha de vencimiento de ' + label + '.');
          return;
        }
      }

      final hasAnyValue = draft.number.text.trim().isNotEmpty ||
          draft.frontPath?.isNotEmpty == true ||
          draft.backPath?.isNotEmpty == true ||
          draft.selfiePath?.isNotEmpty == true;
      if (!hasAnyValue && requirement['required'] != true) continue;

      docs.add({
        'requirement_id': id,
        'document_type': _text(requirement['code'], 'document'),
        'document_number': draft.number.text.trim(),
        'front_object_path': draft.frontPath,
        'back_object_path': draft.backPath,
        'selfie_object_path': draft.selfiePath,
        'expires_at': draft.expiryDate == null ? null
            : '${draft.expiryDate!.year.toString().padLeft(4, '0')}-'
              '${draft.expiryDate!.month.toString().padLeft(2, '0')}-'
              '${draft.expiryDate!.day.toString().padLeft(2, '0')}',
      });
    }

    if (docs.isEmpty) {
      _snack('No hay documentos nuevos o rechazados para enviar.');
      return;
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
        action = _saveFocusedProfilePhoto;
        label = 'Guardar foto de perfil';
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
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: .55),
            ),
          ),
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
    brand.dispose();
    model.dispose();
    color.dispose();
    plate.dispose();
    year.dispose();
    for (final draft in _documents.values) {
      draft.dispose();
    }
    _approvalWatcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_focusedEdit) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(_focusedTitle()),
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Theme.of(context).colorScheme.surface,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            ExpressMotionEntrance(
              duration: ExpressMotion.emphasis,
              child: _focusedContent(),
            ),
          ],
        ),
        bottomNavigationBar: _focusedFooter(),
      );
    }

    final flowSteps = _flowSteps;
    final safeStep = step.clamp(0, flowSteps.length - 1).toInt();
    final isReviewStep = flowSteps[safeStep] == 'review';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.editExisting ? 'Vehículo y documentos' : 'Registro de conductor',
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Theme.of(context).colorScheme.surface,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  ExpressMotionEntrance(
                    duration: ExpressMotion.emphasis,
                    child: _statusCard(),
                  ),
                  const SizedBox(height: 12),
                  _flowMotionHeader(flowSteps, safeStep),
                  const SizedBox(height: 12),
                  ExpressMotionSwap(
                    alignment: Alignment.topCenter,
                    duration: ExpressMotion.emphasis,
                    incomingOffset: const Offset(.045, 0),
                    child: Stepper(
                      key: ValueKey(
                        'driver-step-' +
                            safeStep.toString() +
                            '-' +
                            flowSteps[safeStep],
                      ),
                      currentStep: safeStep,
                      onStepTapped: saving
                          ? null
                          : (value) => setState(() => step = value),
                      controlsBuilder: (_, __) => const SizedBox.shrink(),
                      physics: const NeverScrollableScrollPhysics(),
                      steps: [
                        for (var i = 0; i < flowSteps.length; i++)
                          _buildFlowStep(flowSteps[i], i),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: .55),
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (safeStep > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: saving ? null : _back,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Atrás'),
                      ),
                    ),
                  if (safeStep > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed:
                          saving ? null : (isReviewStep ? _submit : _continue),
                      icon: ExpressMotionSwap(
                        duration: ExpressMotion.fast,
                        child: saving
                            ? const SizedBox.square(
                                key: ValueKey('driver-footer-saving'),
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                isReviewStep
                                    ? Icons.send_rounded
                                    : Icons.arrow_forward_rounded,
                                key: ValueKey(
                                  isReviewStep
                                      ? 'driver-footer-send-icon'
                                      : 'driver-footer-next-icon',
                                ),
                              ),
                      ),
                      label: ExpressMotionSwap(
                        duration: ExpressMotion.fast,
                        child: Text(
                          isReviewStep
                              ? 'Enviar para aprobación'
                              : 'Continuar',
                          key: ValueKey(
                            isReviewStep
                                ? 'driver-footer-send-label'
                                : 'driver-footer-next-label',
                          ),
                        ),
                      ),
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
  late final DriverRegistrationStatusWatcher _statusWatcher;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _statusWatcher = DriverRegistrationStatusWatcher(
      userId: widget.service.userId,
      onChanged: _reload,
      // Documents are not published in Realtime; check infrequently while
      // this detail screen is open even if the admin sends no notification.
      fallbackEvery: const Duration(seconds: 60),
    )..start();
  }

  @override
  void dispose() {
    _statusWatcher.dispose();
    super.dispose();
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
    Map<String, dynamic> manualKyc = <String, dynamic>{};
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
    try {
      manualKyc = _asMap(
        await supabase.rpc('driver_kyc_bolivia_review_state'),
      );
    } catch (_) {}

    List<Map<String, dynamic>> expiryNotices = const [];
    try {
      expiryNotices = _asList(await supabase.rpc('my_driver_expiration_notices'));
    } catch (_) {
      // Before the migration, the existing driver page must still work.
    }
    final profilePhotoPath = _value(profile['profile_photo_path']);
    return <String, dynamic>{
      'state': state,
      'catalog': catalog,
      'manual_kyc': manualKyc,
      'profile_photo_path': profilePhotoPath,
      'expiry_notices': expiryNotices,
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

  Future<void> _openCorrection([String? slot]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverKycCorrectionPage(focusSlot: slot),
      ),
    );
    if (mounted) _reload();
  }

  bool _isIdentityRequirement(Map<String, dynamic> requirement) {
    final code = _value(requirement['code']).toLowerCase();
    final label = _value(requirement['label']).toLowerCase();
    // Persisted driver_documents have document_type, not catalog code/label.
    final type = _value(requirement['document_type']).toLowerCase();
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
      (token) => code.contains(token) || label.contains(token) || type.contains(token),
    );
  }

  bool _documentComplete(
    Map<String, dynamic> requirement,
    Map<String, dynamic>? document,
  ) {
    if (document == null) return false;
    final status = _value(document['status']).toLowerCase();
    if (status != 'verified' && status != 'approved') return false;
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
          final catalog = _asMap(data['catalog']);
          final requirements = _asList(catalog['document_requirements']);
          final documents = _asList(state['documents']);
          final profilePhotoPath = _value(data['profile_photo_path']);
          final manualKyc = _asMap(data['manual_kyc']);
          final expiryNotices = _asList(data['expiry_notices']);
          final reviewParts = _asMap(manualKyc['review_parts']);
          final manualDocument = documents.where((row) =>
              _isIdentityRequirement(row) &&
              _value(row['verification_method']).toLowerCase() == 'manual'
            ).toList();
          final manualStatus = manualDocument.isEmpty
              ? 'not_uploaded'
              : _value(manualDocument.first['status']).toLowerCase();

          String partStatus(String slot) =>
              _value(_asMap(reviewParts[slot])['status']).toLowerCase();
          String partReason(String slot) =>
              _value(_asMap(reviewParts[slot])['reason']);

          final identitySlots = <String>['front', 'back', 'selfie'];
          final identityRejected = identitySlots
              .where((slot) => partStatus(slot) == 'rejected')
              .toList();
          final identityPending = identitySlots
              .where((slot) {
                final status = partStatus(slot);
                return status.isNotEmpty && status != 'approved' && status != 'rejected';
              })
              .toList();
          final identityVerified = manualStatus == 'verified' &&
              (reviewParts.isEmpty ||
                  identitySlots.every((slot) => partStatus(slot) == 'approved'));

          String slotLabel(String slot) => switch (slot) {
                'front' => 'frente del carné',
                'back' => 'reverso del carné',
                'selfie' => 'fotografía facial',
                _ => slot,
              };

          final identityStatus = manualDocument.isEmpty
              ? 'Falta enviar documentos'
              : identityRejected.isNotEmpty
                  ? 'Rechazado: ' +
                      identityRejected.map(slotLabel).join(', ')
                  : identityPending.isNotEmpty || !identityVerified
                      ? 'Documentos pendientes de revisión'
                      : 'Identidad aprobada';

          final profilePart = _asMap(reviewParts['profile']);
          final profileReviewStatus = _value(profilePart['status']).toLowerCase();
          final profileReason = _value(profilePart['reason']);
          final profileStatus = profilePhotoPath.isEmpty
              ? 'Falta completar'
              : profileReviewStatus == 'approved'
                  ? 'Foto de perfil aprobada'
                  : profileReviewStatus == 'rejected'
                      ? 'Foto de perfil rechazada'
                      : 'Foto de perfil en revisión';

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
                for (final notice in expiryNotices) ...[
                  _HintCard(
                    icon: notice['expired'] == true
                        ? Icons.error_outline_rounded
                        : Icons.event_busy_outlined,
                    title: notice['expired'] == true
                        ? 'Documento vencido'
                        : 'Tu documento se vencerá pronto',
                    text: _value(notice['label']) +
                        (notice['expired'] == true
                          ? ': actualízalo para volver a recibir viajes.'
                          : ': faltan ${notice['days_left']} días. Puedes renovarlo en esta pantalla.'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_value(profile['approval_status']).toLowerCase() == 'pending' &&
                    _value(profile['onboarding_completed_at']).isNotEmpty) ...[
                  const _HintCard(
                    icon: Icons.hourglass_top_rounded,
                    title: 'Tus documentos siguen en revisión',
                    text: 'Puedes consultar el estado de cada documento aquí. '
                        'Express te avisará si alguno necesita corrección.',
                  ),
                  const SizedBox(height: 12),
                ],
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
                  subtitle: identityRejected.isNotEmpty
                      ? 'Corrige únicamente ' +
                          identityRejected.map(slotLabel).join(' y ') +
                          '. Lo aprobado permanece válido.'
                      : identityVerified
                          ? 'Frente, reverso y fotografía facial están aprobados.'
                          : 'Tu carné está en revisión. No vuelvas a cargar partes que ya estén aprobadas.',
                  status: identityStatus,
                  actionLabel: manualDocument.isEmpty
                      ? 'Verificar'
                      : identityRejected.isNotEmpty
                          ? 'Corregir'
                          : 'Revisar',
                  onTap: manualDocument.isEmpty
                      ? () => _openSection('identity', step: 1)
                      : () => _openCorrection(
                            identityRejected.isEmpty
                                ? null
                                : identityRejected.first,
                          ),
                ),
                _summaryCard(
                  icon: Icons.account_circle_outlined,
                  title: 'Foto de perfil',
                  subtitle: profileReviewStatus == 'rejected'
                      ? (profileReason.isEmpty
                          ? 'El administrador rechazó únicamente tu foto de perfil.'
                          : 'Motivo: ' + profileReason)
                      : profileReviewStatus == 'approved'
                          ? 'Tu foto de perfil fue aprobada. No necesitas volver a cargarla.'
                          : profilePhotoPath.isEmpty
                              ? 'Todavía falta cargar tu foto de perfil.'
                              : 'Tu foto de perfil está esperando revisión.',
                  status: profileStatus,
                  actionLabel: profilePhotoPath.isEmpty
                      ? 'Completar'
                      : profileReviewStatus == 'rejected'
                          ? 'Corregir'
                          : 'Revisar',
                  onTap: profilePhotoPath.isEmpty ||
                          (manualDocument.isEmpty &&
                              profileReviewStatus == 'rejected')
                      ? () => _openSection('profile', step: 1)
                      : manualDocument.isEmpty
                          ? () => showDialog<void>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Foto de perfil'),
                                  content: Text(profileReviewStatus == 'approved'
                                      ? 'Tu fotografía está aprobada y guardada. '
                                        'No tienes que volver a subirla.'
                                      : 'Tu fotografía ya está guardada y '
                                        'esperando revisión. No necesitas repetir '
                                        'la carga de tu documento.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Entendido'),
                                    ),
                                  ],
                                ),
                              )
                          : () => _openCorrection('profile'),
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
                  Builder(
                    builder: (context) {
                      final rejectedNames = requiredExtra.where((row) {
                        final doc = documentsByRequirement[_value(row['id'])];
                        return _value(doc?['status']).toLowerCase() == 'rejected';
                      }).map((row) => _value(row['label'])).where((e) => e.isNotEmpty).toList();
                      final pendingNames = requiredExtra.where((row) {
                        final doc = documentsByRequirement[_value(row['id'])];
                        final status = _value(doc?['status']).toLowerCase();
                        return status == 'pending';
                      }).map((row) => _value(row['label'])).where((e) => e.isNotEmpty).toList();

                      final allApproved = requiredExtra.isEmpty ||
                          completedExtra == requiredExtra.length;
                      final detail = rejectedNames.isNotEmpty
                          ? 'Rechazado: ' + rejectedNames.join(', ') +
                              '. Corrige solo ese documento.'
                          : pendingNames.isNotEmpty
                              ? 'En revisión: ' + pendingNames.join(', ') + '.'
                              : requiredExtra.isEmpty
                                  ? 'Tu ciudad tiene documentos opcionales que puedes revisar.'
                                  : completedExtra.toString() +
                                      ' de ' +
                                      requiredExtra.length.toString() +
                                      ' requisito(s) obligatorio(s) aprobados.';

                      return _summaryCard(
                        icon: Icons.description_outlined,
                        title: 'Documentos adicionales',
                        subtitle: detail,
                        status: rejectedNames.isNotEmpty
                            ? 'Hay documentos rechazados'
                            : allApproved
                                ? 'Documentos aprobados'
                                : 'Faltan o están en revisión',
                        actionLabel: rejectedNames.isNotEmpty ? 'Corregir' : 'Revisar',
                        onTap: () => _openSection('documents', step: 3),
                      );
                    },
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
  String status = 'not_started';
  String rejectionReason = '';
  Map<String, dynamic> reviewParts = <String, dynamic>{};
  bool dirty = false;
  DateTime? expiryDate;

  // Una foto cargada no equivale a una foto aprobada.
  String slotStatus(String slot) {
    final path = switch (slot) {
      'front' => frontPath,
      'back' => backPath,
      'selfie' => selfiePath,
      _ => null,
    };
    if (path == null || path.isEmpty) return 'missing';
    final raw = reviewParts[slot];
    if (raw is Map) {
      final reviewedPath = raw['path']?.toString();
      if (reviewedPath == path) {
        final state = raw['status']?.toString().toLowerCase();
        if (state == 'approved' || state == 'rejected' || state == 'pending') {
          return state!;
        }
      }
      // Al reemplazar una foto rechazada, el nuevo archivo espera guardado.
      return 'ready';
    }
    if (approved) return 'approved';
    if (rejected) return 'rejected';
    if (pending) return 'pending';
    return 'ready';
  }

  bool get approved => status == 'verified' || status == 'approved';
  bool get rejected => status == 'rejected';
  bool get pending => status == 'pending';

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
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark
            ? scheme.primary.withValues(alpha: .12)
            : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
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
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: complete
          ? (dark
              ? const Color(0xFF067647).withValues(alpha: .14)
              : const Color(0xFFECFDF3))
          : scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: complete
                  ? const Color(0xFF067647).withValues(alpha: .45)
                  : Theme.of(context).dividerColor.withValues(alpha: .55),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: complete
                    ? const Color(0xFF067647).withValues(alpha: .16)
                    : scheme.primary.withValues(alpha: .12),
                child: Icon(
                  complete ? Icons.check_rounded : icon,
                  color: complete ? const Color(0xFF067647) : scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
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
  final String status;
  final IconData icon;
  final VoidCallback? onPressed;

  const _DocButton({
    required this.label,
    required this.status,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final approved = status == 'approved';
    final rejected = status == 'rejected';
    final waiting = status == 'pending' || status == 'ready';
    final tone = approved
        ? const Color(0xFF067647)
        : rejected
            ? const Color(0xFFB42318)
            : waiting
                ? const Color(0xFFB54708)
                : Theme.of(context).colorScheme.primary;
    final mark = approved
        ? Icons.check_circle_rounded
        : rejected
            ? Icons.cancel_rounded
            : waiting
                ? Icons.schedule_rounded
                : icon;
    final suffix = approved
        ? ' ✓'
        : rejected
            ? ' ✕ Rechazado'
            : status == 'pending'
                ? ' · En revisión'
                : status == 'ready'
                    ? ' · Por guardar'
                    : ' · Falta cargar';
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(mark, color: tone),
      label: Text(label + suffix),
      style: OutlinedButton.styleFrom(foregroundColor: tone),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: muted))),
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
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: .55),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

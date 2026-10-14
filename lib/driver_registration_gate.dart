import 'core/supabase_client.dart';
import 'services/express_service.dart';

/// Requisitos que faltan para que un conductor pueda conectarse.
///
/// Reglas: documentos y vehículo obligatorios según el onboarding.
/// El permiso para conectarse por suscripción lo decide el servidor,
/// incluyendo la política de la zona y las excepciones ya autorizadas.
/// El cliente nunca usa el mero estado de facturación como autorización.
List<String> driverRegistrationMissingItems({
  required Map<String, dynamic> state,
  required List<Map<String, dynamic>> requirements,
  required bool subscriptionUsable,
  required bool subscriptionRequired,
  bool expirationEnforced = false,
}) {
  final missing = <String>[];
  final documents = _asList(state['documents']);
  final vehicle = _asMap(state['vehicle']);

  final identityDocs = documents
      .where((row) =>
          _isIdentityRequirement(row) &&
          _value(row['verification_method']).toLowerCase() == 'manual')
      .toList();

  if (identityDocs.isEmpty) {
    missing.add('Documento de identidad: falta enviar el carné.');
  } else {
    final identity = identityDocs.first;
    final identityStatus = _value(identity['status']).toLowerCase();
    final parts = _asMap(identity['review_parts']);

    if (parts.isEmpty) {
      // Compatibility with records created before per-photo review existed.
      if (identityStatus != 'verified') {
        missing.add('Documento de identidad: falta verificar tu identidad.');
      }
    } else {
      void checkPart(String slot, String label) {
        final entry = _asMap(parts[slot]);
        final path = _value(entry['path']);
        final status = _value(entry['status']).toLowerCase();
        final reason = _value(entry['reason']);

        if (path.isEmpty) {
          missing.add('$label: falta cargarlo.');
          return;
        }
        if (status == 'approved') return;
        if (status == 'rejected') {
          missing.add(
            reason.isEmpty ? '$label: rechazado.' : '$label: rechazado · $reason',
          );
          return;
        }
        missing.add('$label: pendiente de aprobación.');
      }

      checkPart('front', 'Carné · frente');
      checkPart('back', 'Carné · reverso');
      checkPart('selfie', 'Fotografía facial');
      checkPart('profile', 'Foto de perfil');
    }
  }

  final vehicleComplete = _value(vehicle['brand']).isNotEmpty &&
      _value(vehicle['model']).isNotEmpty &&
      _value(vehicle['plate']).isNotEmpty;
  if (!vehicleComplete) {
    missing.add('Datos del vehículo: marca, modelo y placa son obligatorios.');
  }

  final documentsByRequirement = <String, Map<String, dynamic>>{
    for (final row in documents)
      if (_value(row['requirement_id']).isNotEmpty)
        _value(row['requirement_id']): row,
  };

  for (final requirement in requirements.where(
    (row) => !_isIdentityRequirement(row) && row['required'] == true,
  )) {
    final id = _value(requirement['id']);
    final label = _value(requirement['label']).isEmpty
        ? 'Documento obligatorio'
        : _value(requirement['label']);
    final document = documentsByRequirement[id];

    if (document == null) {
      missing.add('$label: falta enviarlo.');
      continue;
    }

    final status = _value(document['status']).toLowerCase();
    final reason = _value(
      document['rejection_reason'] ?? document['notes'],
    );
    final expiresAt = DateTime.tryParse(
      _value(document['expires_at']),
    )?.toUtc();
    if (expirationEnforced && expiresAt != null &&
        !expiresAt.isAfter(DateTime.now().toUtc())) {
      missing.add('$label: vencido. Actualiza y espera aprobación.');
      continue;
    }
    if (expirationEnforced &&
        requirement['expiration_required'] == true &&
        expiresAt == null) {
      final submitted = DateTime.tryParse(
        _value(document['created_at']),
      )?.toUtc();
      final enforced = DateTime.tryParse(
        _value(requirement['expiration_required_since']),
      )?.toUtc();
      if (submitted != null && enforced != null &&
          !submitted.isBefore(enforced)) {
        missing.add('$label: falta fecha de vencimiento.');
        continue;
      }
    }

    if (status == 'rejected') {
      missing.add(
        reason.isEmpty ? '$label: rechazado.' : '$label: rechazado · $reason',
      );
      continue;
    }

    if (!_documentComplete(requirement, document)) {
      missing.add('$label: falta completar información o fotografías.');
      continue;
    }

    if (status != 'verified' && status != 'approved') {
      missing.add('$label: pendiente de aprobación.');
    }
  }

  if (subscriptionRequired && !subscriptionUsable) {
    missing.add('Suscripción: activa un plan para conectarte.');
  }
  return missing;
}
/// Carga el estado de registro y devuelve lo que falta. Si algo falla, lanza
/// excepción: el llamador debe no conectar (fail closed).
Future<List<String>> driverRegistrationMissing(ExpressService service) async {
  final state = _asMap(await supabase.rpc('my_driver_onboarding_state'));
  Map<String, dynamic> catalog = <String, dynamic>{};
  final profile = _asMap(state['profile']);
  final country = _value(profile['country_code']).toUpperCase();
  final zone = _value(profile['zone_id']);
  catalog = _asMap(
    await supabase.rpc(
      'driver_onboarding_catalog',
      params: {
        'p_country_code': country.isEmpty ? null : country,
        'p_zone_id': zone.isEmpty ? null : zone,
        'p_lat': null,
        'p_lng': null,
      },
    ),
  );
  // Debe coincidir con la compuerta real de conexión y despacho del backend.
  // Los fallos del RPC se propagan para impedir conectarse sin validar.
  final subscriptionAllowed = await service.driverSubscriptionAllowsDispatch();
  // The shared database is rolling out expiry enforcement Preview-first.
  // The server trigger remains authoritative if the status RPC fails.
  var expirationEnforced = false;
  try {
    expirationEnforced =
        await supabase.rpc('my_driver_expiration_enforced') == true;
  } catch (_) {}
  return driverRegistrationMissingItems(
    state: state,
    requirements: _asList(catalog['document_requirements']),
    subscriptionUsable: subscriptionAllowed,
    // El servidor ya calculó si se exige el plan: no duplicar la política.
    subscriptionRequired: true,
    expirationEnforced: expirationEnforced,
  );
}

bool _isIdentityRequirement(Map<String, dynamic> requirement) {
  final code = _value(requirement['code']).toLowerCase();
  final label = _value(requirement['label']).toLowerCase();
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
    (token) =>
        code.contains(token) || label.contains(token) || type.contains(token),
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

Map<String, dynamic> _asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _asList(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
    : <Map<String, dynamic>>[];

String _value(dynamic value) => value?.toString().trim() ?? '';

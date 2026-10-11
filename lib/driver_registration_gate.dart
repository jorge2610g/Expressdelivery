import 'core/supabase_client.dart';
import 'services/express_service.dart';

/// Requisitos que faltan para que un conductor pueda conectarse.
///
/// Reglas (decisión del propietario): sin documentos verificados, vehículo
/// completo ni suscripción activa no hay conexión. Replica los cálculos de
/// la pantalla de registro (`driver_setup.dart`) sin cambiarlos.
List<String> driverRegistrationMissingItems({
  required Map<String, dynamic> state,
  required List<Map<String, dynamic>> requirements,
  required bool subscriptionUsable,
  bool subscriptionRequired = true,
}) {
  final missing = <String>[];
  final documents = _asList(state['documents']);
  final vehicle = _asMap(state['vehicle']);

  // Una identidad aprobada basta aunque exista un envío más reciente en
  // revisión (la lista viene ordenada por última actualización).
  final identityVerified = documents.any((row) =>
      _isIdentityRequirement(row) &&
      _value(row['verification_method']).toLowerCase() == 'manual' &&
      _value(row['status']).toLowerCase() == 'verified');
  if (!identityVerified) {
    missing.add('Documento de identidad: falta verificar tu identidad.');
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
  final requiredExtra = requirements
      .where((row) => !_isIdentityRequirement(row) && row['required'] == true)
      .toList();
  final pendingExtra = requiredExtra
      .where((row) => !_documentComplete(
            row,
            documentsByRequirement[_value(row['id'])],
          ))
      .length;
  if (pendingExtra > 0) {
    missing.add(
      'Documentos obligatorios: faltan $pendingExtra de ${requiredExtra.length}.',
    );
  }

  // La suscripción solo bloquea donde la zona la exige (feature + enforce),
  // igual que el resto de la app y que my_driver_subscription_state.
  if (subscriptionRequired && !subscriptionUsable) {
    missing.add('Suscripción: activa un plan para conectarte.');
  }
  return missing;
}

/// Carga el estado de registro y devuelve lo que falta. Si algo falla, lanza
/// excepción: el llamador debe no conectar (fail closed).
Future<List<String>> driverRegistrationMissing(ExpressService service) async {
  // Cuentas de auditoría QA (miembros activos de audit_test_groups): no piden
  // documentos ni suscripción. La base ya exime la suscripción a estos miembros.
  // Para cualquier otra cuenta la RPC devuelve false y se aplica la regla normal.
  final uid = supabase.auth.currentUser?.id ?? '';
  if (uid.isNotEmpty) {
    final isQa = await supabase.rpc(
      'is_active_audit_user',
      params: {'p_user_id': uid},
    );
    if (isQa == true) return <String>[];
  }
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
  final subscription = await service.driverSubscriptionState();
  return driverRegistrationMissingItems(
    state: state,
    requirements: _asList(catalog['document_requirements']),
    subscriptionUsable: subscription['usable'] == true,
    // Sin respuesta de suscripción se exige por seguridad (fail closed).
    subscriptionRequired: subscription.isEmpty ||
        (subscription['feature_enabled'] == true &&
            subscription['enforce_access'] == true),
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

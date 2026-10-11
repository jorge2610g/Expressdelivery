import 'core/supabase_client.dart';
import 'services/express_service.dart';

/// Requisitos que faltan para que un conductor pueda conectarse.
///
/// Reglas: documentos de identidad y vehículo completos, más permiso real
/// del servidor para trabajar. Un plan vencido solo bloquea donde se exige
/// suscripción; las cuentas QA mantienen su excepción ya autorizada.
List<String> driverRegistrationMissingItems({
  required Map<String, dynamic> state,
  required List<Map<String, dynamic>> requirements,
  required bool subscriptionAllowed,
}) {
  final missing = <String>[];
  final documents = _asList(state['documents']);
  final vehicle = _asMap(state['vehicle']);

  final identityDocs = documents
      .where((row) =>
          _isIdentityRequirement(row) &&
          _value(row['verification_method']).toLowerCase() == 'manual')
      .toList();
  final identityStatus =
      identityDocs.isEmpty ? '' : _value(identityDocs.first['status']).toLowerCase();
  if (identityStatus != 'verified') {
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

  if (!subscriptionAllowed) {
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
  // The RPC is also used by backend online/dispatch guards, which account
  // for zone settings and QA membership. A plan's billing 'usable' flag alone
  // is not an authorization decision.
  final subscriptionAllowed = await service.driverSubscriptionAllowsDispatch();
  return driverRegistrationMissingItems(
    state: state,
    requirements: _asList(catalog['document_requirements']),
    subscriptionAllowed: subscriptionAllowed,
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

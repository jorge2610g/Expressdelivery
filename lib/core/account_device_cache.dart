import 'package:shared_preferences/shared_preferences.dart';

/// Caché del dispositivo que pertenece a una cuenta concreta. Se borra al
/// cerrar sesión y cuando otra cuenta entra en el mismo teléfono, para que
/// nunca se muestre ubicación, perfil ni ruta de una cuenta anterior.
///
/// No se borran la sesión de Supabase (la gestiona Supabase) ni la configuración
/// de la app o el estado de cuota de Mapbox (no contienen datos personales).
const String accountUidMarkerKey = 'express_device_account_uid_v1';

/// Claves globales del dispositivo que guardan ubicación o datos de la cuenta.
const List<String> accountDeviceGlobalKeys = <String>[
  'express_last_valid_location_v1',
  'express_processed_push_keys_v1',
];

/// Prefijos de caché por cuenta. Solo se usan para claves que ya están
/// ligadas a un identificador de usuario.
const List<String> accountDeviceKeyPrefixes = <String>[
  'express_account_bootstrap_v1_',
  'express_passenger_landing_v1_',
];

// Cola de operaciones de caché. Cada cambio de cuenta o cierre de sesión se
// encadena aquí, y quien lee caché de dispositivo espera a la cola. Así una
// lectura no puede ver datos de la cuenta anterior mientras se borran.
Future<void> _accountCacheQueue = Future<void>.value();

Future<void> _enqueue(Future<void> Function() operation) {
  final next = _accountCacheQueue.catchError((_) {}).then((_) => operation());
  _accountCacheQueue = next.catchError((_) {});
  return next;
}

/// Espera a que termine cualquier borrado o cambio de cuenta pendiente.
/// Llamar antes de leer caché compartida del dispositivo.
Future<void> awaitAccountDeviceCacheReady() =>
    _accountCacheQueue.catchError((_) {});

/// Borra toda la caché del dispositivo asociada a la cuenta. [clearMemory]
/// limpia las cachés en memoria de los módulos del proceso.
Future<void> clearAccountDeviceCaches({void Function()? clearMemory}) =>
    _enqueue(() => _clearNow(clearMemory: clearMemory));

Future<void> _clearNow({void Function()? clearMemory}) async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in accountDeviceGlobalKeys) {
    await prefs.remove(key);
  }
  for (final key in prefs.getKeys().toList()) {
    if (accountDeviceKeyPrefixes.any(key.startsWith)) {
      await prefs.remove(key);
    }
  }
  await prefs.remove(accountUidMarkerKey);
  clearMemory?.call();
}

/// Si [uid] no coincide con la cuenta que escribió la caché del dispositivo,
/// borra esa caché antes de que la app la lea. Sin marcador (primer uso o
/// instalación previa) también se borra: es más seguro reconstruirla.
Future<void> switchAccountDeviceCachesIfNeeded(
  String? uid, {
  void Function()? clearMemory,
}) {
  if (uid == null || uid.isEmpty) return Future<void>.value();
  return _enqueue(() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(accountUidMarkerKey) == uid) return;
    await _clearNow(clearMemory: clearMemory);
    await prefs.setString(accountUidMarkerKey, uid);
  });
}

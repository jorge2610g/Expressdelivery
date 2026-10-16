import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Estado de conectividad observado a partir de las propias llamadas al
/// servidor. No usa un paquete de conectividad: un error de red es evidencia
/// suficiente y una lectura correcta demuestra que hay conexión.
enum ExpressConnectionState { online, reconnecting, offline }

/// Clasifica un error como fallo de red (sin conexión, tiempo agotado, TLS).
/// Los errores del servidor o de datos no son fallos de red: el servidor
/// respondió, así que la conexión existe.
bool isExpressNetworkFailure(Object error) {
  if (error is TimeoutException || error is http.ClientException) return true;
  // Tipos de dart:io y del cliente de autenticación. Se comparan por nombre
  // para que el módulo siga compilando en web.
  switch (error.runtimeType.toString()) {
    case 'SocketException':
    case 'HandshakeException':
    case 'AuthRetryableFetchException':
      return true;
  }
  return false;
}

/// Texto breve de antigüedad para mostrar junto a datos guardados.
String expressFreshnessLabel(DateTime savedAt, DateTime now) {
  final age = now.difference(savedAt);
  if (age.isNegative || age < const Duration(minutes: 1)) return 'hace un momento';
  if (age < const Duration(hours: 1)) return 'hace ${age.inMinutes} min';
  if (age < const Duration(days: 1)) return 'hace ${age.inHours} h';
  return 'hace ${age.inDays} días';
}

/// Máquina de estados de conexión:
/// - online → reconnecting tras un fallo de red;
/// - reconnecting → offline tras tres fallos consecutivos;
/// - cualquier estado → online tras una lectura correcta.
/// La recuperación es automática: un temporizador con espera creciente lanza
/// una sonda de solo lectura, y al volver a primer plano se sondea de inmediato.
class ExpressConnectivityMonitor extends ChangeNotifier {
  ExpressConnectivityMonitor({
    Timer Function(Duration delay, void Function() callback)? scheduler,
    DateTime Function()? clock,
  })  : _schedule =
            scheduler ?? ((delay, callback) => Timer(delay, callback)),
        _clock = clock ?? DateTime.now;

  /// Espera entre sondas: 2, 4, 8, 16 y luego 30 s como máximo.
  static const List<Duration> backoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  static const int offlineAfterFailures = 3;

  /// Instancia compartida por la app. Las pruebas crean la suya.
  static final ExpressConnectivityMonitor instance =
      ExpressConnectivityMonitor();

  final Timer Function(Duration delay, void Function() callback) _schedule;
  final DateTime Function() _clock;
  final Map<String, DateTime> _lastValidAt = <String, DateTime>{};

  ExpressConnectionState _state = ExpressConnectionState.online;
  int _consecutiveFailures = 0;
  int _backoffIndex = 0;
  Timer? _probeTimer;

  /// Sonda de solo lectura. Devuelve normalmente o lanza el error original.
  /// Debe ser barata y no tener efectos: nunca una escritura.
  Future<void> Function()? probe;

  ExpressConnectionState get state => _state;
  bool get isOnline => _state == ExpressConnectionState.online;

  /// Momento de la última respuesta válida de una fuente concreta. Solo se
  /// fija tras una lectura correcta; nunca al leer caché ni al aplicar
  /// cambios optimistas.
  DateTime? lastValidAt(String source) => _lastValidAt[source];

  /// Registra una lectura correcta de [source] y restablece la conexión.
  void recordSuccess(String source) {
    _lastValidAt[source] = _clock();
    _consecutiveFailures = 0;
    _backoffIndex = 0;
    _probeTimer?.cancel();
    _probeTimer = null;
    _setState(ExpressConnectionState.online);
  }

  /// Registra un fallo. Solo los fallos de red cambian el estado.
  void recordFailure(Object error) {
    if (!isExpressNetworkFailure(error)) return;
    _consecutiveFailures++;
    _setState(_consecutiveFailures >= offlineAfterFailures
        ? ExpressConnectionState.offline
        : ExpressConnectionState.reconnecting);
    _scheduleProbe();
  }

  /// Sondea ahora. Llamar al volver a primer plano o desde un botón de
  /// reintento. No hace nada si ya hay conexión.
  Future<void> probeNow() async {
    _probeTimer?.cancel();
    _probeTimer = null;
    final run = probe;
    if (run == null) return;
    try {
      await run();
      recordSuccess('probe');
    } catch (error) {
      if (isExpressNetworkFailure(error)) {
        recordFailure(error);
      } else {
        // El servidor respondió con un error de datos: la conexión existe.
        recordSuccess('probe');
      }
    }
  }

  /// Vuelve al estado inicial al cambiar de cuenta: olvida fuentes válidas,
  /// la sonda de la cuenta anterior y cualquier reintento pendiente.
  void resetForAccountChange() {
    _probeTimer?.cancel();
    _probeTimer = null;
    probe = null;
    _lastValidAt.clear();
    _consecutiveFailures = 0;
    _backoffIndex = 0;
    _setState(ExpressConnectionState.online);
  }

  void onAppResumed() {
    if (!isOnline) unawaited(probeNow());
  }

  void _scheduleProbe() {
    _probeTimer?.cancel();
    final index = _backoffIndex < backoff.length ? _backoffIndex : backoff.length - 1;
    _backoffIndex++;
    _probeTimer = _schedule(backoff[index], () => unawaited(probeNow()));
  }

  void _setState(ExpressConnectionState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    super.dispose();
  }
}

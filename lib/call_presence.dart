import 'dart:async';

import 'services/express_service.dart';

/// Informa al servidor si la app está dentro o fuera de primer plano. Las
/// llamadas usan ese dato: si la otra persona está dentro, suena como siempre;
/// si está fuera, solo puede sonar con sobreposición de pantalla.
///
/// Se reporta al abrir, al pasar a segundo plano y con un latido cada minuto
/// mientras la app está abierta. Si la app se cierra sin avisar, la presencia
/// vence sola a los 90 segundos.
class ExpressCallPresence {
  ExpressCallPresence._();

  static Timer? _heartbeat;
  static ExpressService? _service;

  static void start(ExpressService service) {
    _service = service;
    _heartbeat ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => _report(true),
    );
    _report(true);
  }

  static void stop() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _report(false);
  }

  static void _report(bool foreground) {
    final service = _service;
    if (service == null) return;
    unawaited(
      service.setMyPresence(foreground: foreground).catchError((_) {}),
    );
  }
}

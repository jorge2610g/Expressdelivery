/// Cuenta regresiva de abordaje compartida por el pasajero y el conductor.
///
/// La ventana empieza en la marca `driver_waiting_since` que entrega el
/// servidor. Si esa marca aún no llegó, no se inventa un valor: el resultado es
/// null y la UI muestra "Calculando…". Una marca conocida se recuerda para que
/// una reconstrucción sin marca no devuelva el reloj a 5:00.
const int kPickupBoardingWindowSeconds = 5 * 60;

/// Marca de inicio de la espera, o null si el servidor no la entregó.
DateTime? parsePickupWaitStart(String? raw) =>
    DateTime.tryParse(raw ?? '')?.toUtc();

/// Inicio efectivo: la marca actual del servidor o, si falta, la última conocida.
DateTime? effectivePickupWaitStart({
  required DateTime? serverStart,
  required DateTime? lastKnownStart,
}) =>
    serverStart ?? lastKnownStart;

/// Segundos restantes de la ventana (0..300), o null sin marca de inicio.
int? pickupWaitRemainingSeconds({
  required DateTime? start,
  required DateTime now,
}) {
  if (start == null) return null;
  final elapsed = now.toUtc().difference(start.toUtc()).inSeconds;
  return (kPickupBoardingWindowSeconds - elapsed)
      .clamp(0, kPickupBoardingWindowSeconds)
      .toInt();
}

/// Formato m:ss para mostrar en la tarjeta.
String pickupWaitClock(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

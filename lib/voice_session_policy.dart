/// Reglas de renovación de la sesión de llamadas privadas (ZEGOCLOUD).
///
/// El servidor (`zego-call`) entrega una llave que vence a las 6 horas. Si la
/// sesión ya cayó o la última invitación falló, renovar la llave no basta: hay
/// que cerrar la sesión y volver a entrar con la llave nueva.

/// Vida de la llave según la respuesta del servidor. Si falta o no es válida,
/// usa 6 horas, igual que `tokenTtlSeconds` en `zego-call`.
Duration voiceTokenLifetime(Map<String, dynamic> result) {
  final seconds = int.tryParse(
    result['tokenExpiresInSeconds']?.toString() ?? '',
  );
  if (seconds == null || seconds <= 0) {
    return const Duration(hours: 6);
  }
  return Duration(seconds: seconds);
}

/// Indica si hay que volver a entrar a ZEGOCLOUD en lugar de solo renovar la
/// llave:
/// - si la última invitación o el último inicio de sesión falló;
/// - si no se sabe cuándo vence la llave;
/// - si faltan menos de [renewMargin] para que venza. Así se entra de nuevo
///   antes de que el servicio corte la sesión.
bool voiceSessionNeedsFreshLogin({
  required DateTime? tokenExpiresAt,
  required DateTime now,
  required bool lastAttemptFailed,
  Duration renewMargin = const Duration(minutes: 30),
}) {
  if (lastAttemptFailed || tokenExpiresAt == null) return true;
  return !now.add(renewMargin).isBefore(tokenExpiresAt);
}

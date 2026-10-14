/// Stable passenger/driver-facing voice call errors.
///
/// ZEGOCLOUD/Supabase may throw a minified web exception containing
/// HTTP status and an internal code. Never expose those implementation
/// details to an Express rider.
String expressVoiceCallMessage(Object error) {
  final raw = error.toString();
  final normalized = raw.toLowerCase();
  if (normalized.contains('call_cooldown') ||
      (normalized.contains('429') &&
       normalized.contains('volver a llamar'))) {
    return 'Ya intentaste llamar hace poco. Espera unos segundos e inténtalo de nuevo.';
  }
  if (normalized.contains('zego_not_configured') ||
      normalized.contains('zegoflutterengine') ||
      normalized.contains('service_initialized: false')) {
    return 'Las llamadas no están disponibles por el momento. Intenta de nuevo más tarde.';
  }
  if (normalized.contains('trip_not_active')) {
    return 'Solo puedes llamar mientras el viaje esté activo.';
  }
  if (normalized.contains('not_trip_participant')) {
    return 'No tienes permiso para llamar en este viaje.';
  }
  if (normalized.contains('timeout')) {
    return 'La llamada tardó demasiado en conectar. Intenta nuevamente.';
  }
  return 'No se pudo iniciar la llamada. Comprueba tu conexión e inténtalo nuevamente.';
}

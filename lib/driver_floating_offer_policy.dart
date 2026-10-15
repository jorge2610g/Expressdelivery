/// Decide cuándo puede mostrarse una tarjeta flotante de oferta para el
/// conductor. Pura: no toca permisos, red ni la ventana del sistema.
///
/// La ventana real de Android (SYSTEM_ALERT_WINDOW) no está implementada: el
/// repositorio no tiene proyecto Android propio y el permiso requiere cambios
/// en el flujo de compilación de producción (ver docs/reports/ORDEN_013).
/// Esta política solo fija las condiciones que la ventana debe cumplir.
enum FloatingOfferService { taxi, delivery }

class FloatingOfferCandidate {
  const FloatingOfferCandidate({
    required this.service,
    required this.expiresAt,
  });

  final FloatingOfferService service;
  final DateTime expiresAt;
}

class FloatingOfferContext {
  const FloatingOfferContext({
    required this.settingEnabled,
    required this.overlayPermissionGranted,
    required this.driverOnline,
    required this.driverAvailable,
    required this.appInForeground,
    required this.now,
  });

  /// Ajuste voluntario del conductor (nunca activado por defecto).
  final bool settingEnabled;

  /// Permiso «Mostrar sobre otras aplicaciones» concedido por el usuario.
  final bool overlayPermissionGranted;
  final bool driverOnline;
  final bool driverAvailable;
  final bool appInForeground;
  final DateTime now;
}

/// Devuelve true solo cuando la tarjeta puede mostrarse. Cualquier condición
/// falsa, o una oferta ya vencida, impide mostrarla.
bool shouldShowFloatingOffer(
  FloatingOfferContext context,
  FloatingOfferCandidate? offer,
) {
  if (offer == null) return false;
  if (!context.settingEnabled) return false;
  if (!context.overlayPermissionGranted) return false;
  if (!context.driverOnline || !context.driverAvailable) return false;
  // En primer plano la app ya muestra sus propias tarjetas.
  if (context.appInForeground) return false;
  if (!context.now.isBefore(offer.expiresAt)) return false;
  return true;
}

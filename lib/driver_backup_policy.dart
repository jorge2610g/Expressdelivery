/// Respaldo de solicitudes del conductor.
///
/// La fuente principal son Realtime (ride_requests) y las notificaciones push.
/// Mientras el canal de solicitudes está suscrito, el respaldo solo consulta si
/// en los últimos 30 s no hubo ninguna actualización de la pantalla ni por
/// tiempo real. Si el canal no está suscrito (se cayó o aún no conecta), el
/// respaldo vuelve al ritmo original de 12 s.
const Duration driverBackupFallbackInterval = Duration(seconds: 12);
const Duration driverBackupHealthyInterval = Duration(seconds: 30);

/// Decide si el respaldo debe consultar solicitudes en este momento.
///
/// [lastActivityAt] es la última vez que la pantalla se actualizó (por tiempo
/// real, push o refresco). [channelSubscribed] indica que Realtime confirmó la
/// suscripción de solicitudes.
bool driverBackupDue({
  required bool channelSubscribed,
  required DateTime? lastActivityAt,
  required DateTime now,
}) {
  if (!channelSubscribed) return true;
  if (lastActivityAt == null) return true;
  return now.difference(lastActivityAt) >= driverBackupHealthyInterval;
}

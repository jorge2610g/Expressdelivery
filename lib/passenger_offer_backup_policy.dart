/// Respaldo de ofertas del pasajero. El tiempo real es la fuente principal.
/// El respaldo consulta cada 4 s, pero solo si no llegó ninguna actualización
/// por tiempo real en los últimos 5 s.
///
/// Si el tiempo real falla, una oferta puede tardar hasta ~4 s en aparecer:
/// es el margen aceptado para no consultar cada segundo.
const Duration passengerOfferBackupInterval = Duration(seconds: 4);
const Duration passengerOfferRealtimeQuietWindow = Duration(seconds: 5);

/// Decide si el respaldo debe consultar ofertas en este momento.
bool passengerOfferBackupDue({
  required DateTime? lastRealtimeAt,
  required DateTime now,
}) {
  if (lastRealtimeAt == null) return true;
  return now.difference(lastRealtimeAt) >= passengerOfferRealtimeQuietWindow;
}

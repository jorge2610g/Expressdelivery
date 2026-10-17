/// Guardas del pasajero para que un viaje terminado no vuelva a mostrarse como
/// activo ni dispare otra vez la calificación.
///
/// El servidor ya excluye los viajes `completed` y `cancelled` de
/// `passenger_home_state_v2` y `passenger_active_trip_live_state_v2`. Esta guarda
/// cubre lo que llega después desde el cliente: respuestas de lecturas que se
/// lanzaron antes de la finalización, cachés y actualizaciones en vivo.
const Set<String> kTerminalTripStatuses = {'completed', 'cancelled'};

bool isTerminalTripStatus(String? status) =>
    status != null && kTerminalTripStatuses.contains(status);

class PassengerFinishedTrips {
  final Set<String> _finishedIds = <String>{};

  /// Marca un viaje como terminado. Es irreversible dentro del proceso.
  void markFinished(String? tripId) {
    if (tripId == null || tripId.isEmpty) return;
    _finishedIds.add(tripId);
  }

  bool isFinished(String? tripId) =>
      tripId != null && _finishedIds.contains(tripId);

  /// Viaje activo visible: null si el dato ya es terminal o si el id fue
  /// marcado como terminado antes. Un dato terminal también queda marcado.
  Map<String, dynamic>? visibleActiveTrip(Map<String, dynamic>? trip) {
    if (trip == null) return null;
    final tripId = trip['id']?.toString();
    if (isTerminalTripStatus(trip['status']?.toString())) {
      markFinished(tripId);
      return null;
    }
    if (isFinished(tripId)) return null;
    return trip;
  }
}

/// Calificación automática: una sola vez por viaje en todo el proceso, aunque la
/// pantalla se reconstruya. El banner de pendientes sigue disponible.
class PassengerRatingPromptGate {
  final Set<String> _claimedTripIds = <String>{};

  /// true solo la primera vez que se reclama el viaje.
  bool claim(String? tripId) {
    if (tripId == null || tripId.isEmpty) return false;
    return _claimedTripIds.add(tripId);
  }
}

/// Instancias de proceso: sobreviven a la reconstrucción del widget.
final PassengerFinishedTrips passengerFinishedTrips = PassengerFinishedTrips();
final PassengerRatingPromptGate passengerRatingPromptGate =
    PassengerRatingPromptGate();

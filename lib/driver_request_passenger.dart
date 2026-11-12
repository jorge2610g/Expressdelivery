/// Datos del pasajero que el backend adjunta a cada solicitud para el conductor
/// (migración 20261112120000): primer nombre, foto y calificación.
/// El teléfono nunca llega aquí; sigue reservado al viaje activo.
class DriverRequestPassenger {
  const DriverRequestPassenger({
    required this.firstName,
    required this.avatarUrl,
    required this.rating,
    required this.ratingCount,
  });

  final String? firstName;
  final String? avatarUrl;
  final double? rating;
  final int ratingCount;

  /// Devuelve null si la fila no trae ningún dato del pasajero (respuesta
  /// anterior a la migración, o pedido de restaurante/marketplace).
  static DriverRequestPassenger? fromRide(Map<String, dynamic> ride) {
    final hasAny = ride.containsKey('passenger_first_name') ||
        ride.containsKey('passenger_rating_count') ||
        ride.containsKey('passenger_rating') ||
        ride.containsKey('passenger_avatar_url');
    if (!hasAny) return null;

    String? clean(Object? raw) {
      final text = raw?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final rawRating = ride['passenger_rating'];
    final rating = rawRating is num
        ? rawRating.toDouble()
        : double.tryParse(rawRating?.toString() ?? '');
    final rawCount = ride['passenger_rating_count'];
    final count = rawCount is num
        ? rawCount.toInt()
        : int.tryParse(rawCount?.toString() ?? '') ?? 0;

    final avatar = clean(ride['passenger_avatar_url']);
    final avatarUri = avatar == null ? null : Uri.tryParse(avatar);
    final safeAvatar = avatarUri != null &&
            (avatarUri.scheme == 'https' || avatarUri.scheme == 'http')
        ? avatar
        : null;

    return DriverRequestPassenger(
      firstName: clean(ride['passenger_first_name']),
      avatarUrl: safeAvatar,
      rating: rating,
      ratingCount: count < 0 ? 0 : count,
    );
  }

  /// Nombre a mostrar; si no hay nombre, una palabra neutra.
  String get displayName => firstName ?? 'Pasajero';

  bool get hasRating => rating != null && ratingCount > 0;

  /// Línea para la tarjeta: «★ 3.3 · 3 calificaciones» o un texto neutro.
  String get ratingLabel {
    if (!hasRating) return 'Sin calificaciones aún';
    final stars = rating!.toStringAsFixed(1);
    final noun = ratingCount == 1 ? 'calificación' : 'calificaciones';
    return '★ $stars · $ratingCount $noun';
  }

  /// Versión corta para la tarjeta flotante: «Anita ★ 3.3 (3)».
  String get floatingSummary {
    if (!hasRating) return displayName;
    return '$displayName ★ ${rating!.toStringAsFixed(1)} ($ratingCount)';
  }
}

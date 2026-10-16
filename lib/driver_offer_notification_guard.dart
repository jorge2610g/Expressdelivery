import 'package:shared_preferences/shared_preferences.dart';

/// Tiempo durante el que un aviso local tardío de una oferta ya mostrada como
/// barra flotante no debe volver a aparecer. Cubre la carrera en la que el
/// handler de segundo plano publica el aviso después de que la barra ya se
/// mostró. Es mayor que la vigencia habitual de una oferta.
const Duration driverOfferSuppressionWindow = Duration(minutes: 10);

String _suppressionKey(String rideRequestId) =>
    'express_offer_suppressed_v1:$rideRequestId';

/// Marca la oferta como ya atendida por la barra flotante.
Future<void> markDriverOfferSuppressed(
  String rideRequestId, {
  DateTime? now,
}) async {
  if (rideRequestId.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  final until = (now ?? DateTime.now()).add(driverOfferSuppressionWindow);
  await prefs.setInt(
    _suppressionKey(rideRequestId),
    until.millisecondsSinceEpoch,
  );
}

/// Indica si el aviso local de esta oferta debe omitirse por la supresión.
Future<bool> isDriverOfferSuppressed(
  String rideRequestId, {
  DateTime? now,
}) async {
  if (rideRequestId.isEmpty) return false;
  final prefs = await SharedPreferences.getInstance();
  final until = prefs.getInt(_suppressionKey(rideRequestId)) ?? 0;
  return until > (now ?? DateTime.now()).millisecondsSinceEpoch;
}

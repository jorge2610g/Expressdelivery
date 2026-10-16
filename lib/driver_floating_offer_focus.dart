import 'driver_floating_offer_data.dart';
import 'driver_floating_offer_policy.dart';

/// Decide, de forma pura, qué oferta abre la app cuando el conductor pulsa
/// Aceptar en la tarjeta flotante. Revalida la oferta contra los datos ya
/// cargados: si ya no es válida, no se abre nada.
enum FloatingOfferFocusKind { taxi, delivery }

class FloatingOfferFocusTarget {
  const FloatingOfferFocusTarget(this.kind, this.item);

  final FloatingOfferFocusKind kind;
  final Map<String, dynamic> item;
}

FloatingOfferFocusTarget? resolveFloatingOfferFocus({
  required String? offerId,
  required List<Map<String, dynamic>> rides,
  required List<Map<String, dynamic>> deliveries,
  required bool driverOnline,
  required DateTime now,
}) {
  if (offerId == null || offerId.isEmpty || !driverOnline) return null;
  bool fresh(Map<String, dynamic> row, FloatingOfferService service) =>
      driverFloatingOfferMatches(row, offerId, service, now);

  for (final ride in rides) {
    if (ride['id']?.toString() == offerId) {
      return fresh(ride, FloatingOfferService.taxi)
          ? FloatingOfferFocusTarget(FloatingOfferFocusKind.taxi, ride)
          : null;
    }
  }
  for (final delivery in deliveries) {
    if (delivery['id']?.toString() == offerId) {
      return fresh(delivery, FloatingOfferService.delivery)
          ? FloatingOfferFocusTarget(FloatingOfferFocusKind.delivery, delivery)
          : null;
    }
  }
  return null;
}

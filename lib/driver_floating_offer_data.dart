import 'driver_floating_offer_policy.dart';
import 'driver_floating_offers.dart';

/// Converts only currently authorized and unexpired driver-list rows.
/// Missing expiry or ID fails closed; do not fabricate a deadline.
FloatingOfferCard? driverFloatingCardFromRow(
  Map<String, dynamic> row,
  FloatingOfferService service,
  DateTime now, {
  required String Function(Object amount, String currency) formatPrice,
}) {
  if (service == FloatingOfferService.delivery &&
      row['marketplace_order_id'] != null) return null;
  final id = row['id']?.toString().trim() ?? '';
  final expiry = DateTime.tryParse(row['expires_at']?.toString() ?? '')?.toUtc();
  if (id.isEmpty || expiry == null || !expiry.isAfter(now.toUtc())) return null;
  const terminal = <String>{
    'cancelled', 'canceled', 'completed', 'delivered', 'expired',
    'assigned', 'rejected', 'accepted',
  };
  if (terminal.contains(row['status']?.toString().toLowerCase())) return null;

  String? label(Object? raw) {
    final result = raw?.toString().trim();
    return result == null || result.isEmpty ? null : result;
  }

  final pickup = label(row['pickup_address']) ?? 'Origen no disponible';
  final destination = label(service == FloatingOfferService.delivery
      ? row['dropoff_address']
      : row['destination_address']) ?? 'Destino no disponible';
  final currency = label(row['currency']);
  final amount = row['proposed_fare'];
  final priceLabel = currency != null &&
          amount != null &&
          double.tryParse(amount.toString()) != null
      ? formatPrice(amount, currency)
      : 'Precio no disponible';

  return FloatingOfferCard(
    offerId: id,
    service: service,
    priceLabel: priceLabel,
    routeLabel: '$pickup → $destination',
    expiresAt: expiry,
  );
}

/// Only Taxi and package-delivery requests already authorized by backend.
FloatingOfferCard? firstDriverFloatingCard({
  required List<Map<String, dynamic>> rides,
  required List<Map<String, dynamic>> deliveries,
  required DateTime now,
  required String Function(Object amount, String currency) formatPrice,
}) {
  for (final ride in rides) {
    final card = driverFloatingCardFromRow(
      ride, FloatingOfferService.taxi, now, formatPrice: formatPrice);
    if (card != null) return card;
  }
  for (final delivery in deliveries) {
    final card = driverFloatingCardFromRow(
      delivery, FloatingOfferService.delivery, now, formatPrice: formatPrice);
    if (card != null) return card;
  }
  return null;
}

/// Rejects late actions using a newly fetched, authorized row.
bool driverFloatingOfferMatches(
  Map<String, dynamic> row,
  String offerId,
  FloatingOfferService service,
  DateTime now,
) => driverFloatingCardFromRow(
      row, service, now, formatPrice: (amount, currency) => '$currency $amount',
    )?.offerId == offerId;

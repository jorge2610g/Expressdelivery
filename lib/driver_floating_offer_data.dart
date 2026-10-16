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
  var expiry = DateTime.tryParse(row['expires_at']?.toString() ?? '')?.toUtc();
  if (service == FloatingOfferService.delivery && expiry == null) {
    // Verified DB contract (2026-10-15): delivery_requests has created_at but
    // NO expires_at. Cap only the floating card to 3 minutes; this does NOT
    // expire the backend request or assume that the delivery was cancelled.
    final created =
        DateTime.tryParse(row['created_at']?.toString() ?? '')?.toUtc();
    if (created != null) {
      expiry = created.add(const Duration(minutes: 3));
    }
  }
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
  final destination = label(
      service == FloatingOfferService.delivery
          ? (row['dropoff_address'] ?? row['destination_address'])
          : row['destination_address']) ?? 'Destino no disponible';
  final currency = label(row['currency']);
  final amount = row['proposed_fare'];
  // The request's ISO-4217 currency is authoritative, not the driver's
  // phone location. Prefix it when the UI formatter uses a local symbol
  // (CLP $, BOB Bs, etc.) so the amount stays unambiguous across countries.
  String priceLabel = 'Precio no disponible';
  final isoCurrency = currency?.toUpperCase();
  if (isoCurrency != null &&
      isoCurrency.length == 3 &&
      isoCurrency.codeUnits.every((unit) => unit >= 65 && unit <= 90) &&
      amount != null &&
      double.tryParse(amount.toString()) != null) {
    final formatted = formatPrice(amount, isoCurrency);
    priceLabel = formatted.toUpperCase().startsWith(isoCurrency)
        ? formatted
        : isoCurrency + ' ' + formatted;
  }

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
    final service = ride['service_mode'] == 'parcel'
        ? FloatingOfferService.delivery : FloatingOfferService.taxi;
    final card = driverFloatingCardFromRow(
      ride, service, now, formatPrice: formatPrice);
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


/// A native accept is held only briefly while the existing driver screen
/// resumes. A new screen or driver account cannot inherit an old action.
bool driverFloatingActionIsRecent(DateTime acceptedAt, DateTime now) {
  final elapsed = now.toUtc().difference(acceptedAt.toUtc());
  return !elapsed.isNegative && elapsed <= const Duration(minutes: 2);
}

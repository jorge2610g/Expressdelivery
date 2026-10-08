/// Selects the currency displayed in the passenger's ride confirmation.
///
/// The fare RPC calculates a quote from the *pickup coordinates*, while a
/// landing screen may carry a cached zone from another country. Once we have
/// confirmed a route, the backend quote must win over that stale landing.
///
/// This only controls display: the server still validates price, country,
/// currency and minimum when creating the trip.
String passengerRideCurrency({
  required Map<String, dynamic> fareQuote,
  required Map<String, dynamic>? activeZone,
  required bool routeConfirmed,
}) {
  String code(Object? value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';
    return RegExp(r'^[A-Z]{3}$').hasMatch(raw) ? raw : '';
  }

  if (routeConfirmed) {
    final quotedCurrency = code(fareQuote['currency']);
    if (quotedCurrency.isNotEmpty) return quotedCurrency;
  }
  final locationCurrency = code(activeZone?['currency_code']);
  if (locationCurrency.isNotEmpty) return locationCurrency;
  // No GPS/zone/quote yet: never assign an imaginary Bolivia currency.
  return '';
}

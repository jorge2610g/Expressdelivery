double? expressMoneyDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String expressCurrencyCode(Object? raw, {String fallback = 'BOB'}) {
  final code = raw?.toString().trim().toUpperCase();
  if (code == null || code.isEmpty) return fallback.toUpperCase();
  return code;
}

String expressMoney(Object? value, Object? currencyRaw) {
  final amount = expressMoneyDouble(value) ?? 0;
  final currency = expressCurrencyCode(currencyRaw);

  if (currency == 'CLP') {
    final negative = amount < 0;
    final digits = amount.round().abs().toString();
    final reversed = digits.split('').reversed.toList();
    final grouped = <String>[];
    for (var i = 0; i < reversed.length; i++) {
      if (i > 0 && i % 3 == 0) grouped.add('.');
      grouped.add(reversed[i]);
    }
    return 'CLP ' + (negative ? '-' : '') + grouped.reversed.join();
  }

  if (currency == 'BOB') {
    final shown = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return 'Bs ' + shown;
  }

  final shown = amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  return currency + ' ' + shown;
}

String expressTripCurrency(
  Map<String, dynamic> trip, {
  String fallback = 'BOB',
}) {
  final rideRaw = trip['ride_requests'];
  if (rideRaw is Map) {
    final ride = Map<String, dynamic>.from(rideRaw);
    final value = ride['currency'];
    if (value != null && value.toString().trim().isNotEmpty) {
      return expressCurrencyCode(value, fallback: fallback);
    }
  }
  return expressCurrencyCode(
    trip['currency'],
    fallback: fallback,
  );
}

String expressServiceCurrency(
  Map<String, dynamic> row, {
  String fallback = 'BOB',
}) {
  if (row.containsKey('ride_requests')) {
    return expressTripCurrency(row, fallback: fallback);
  }
  return expressCurrencyCode(row['currency'], fallback: fallback);
}

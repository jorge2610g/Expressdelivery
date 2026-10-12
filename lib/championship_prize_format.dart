import 'money_format.dart';

/// Displays the configured prize in the city's currency, including older
/// championships that stored only plain numbers as free-form prize strings.
/// Descriptive/non-cash prizes are preserved verbatim.
String championshipPrizeLabel(Object? raw, Object? currencyRaw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return 'Premio por anunciar';

  final code = expressCurrencyCode(currencyRaw);
  var amountText = value;
  final prefix = RegExp(
    r'^(?:CLP|BOB|Bs\.?|\$)\s*',
    caseSensitive: false,
  );
  final hasPrefix = prefix.hasMatch(amountText);
  if (hasPrefix) {
    amountText = amountText.replaceFirst(prefix, '').trim();
  }

  // Treat '150000', '150.000', '150,000' and '500.50' as cash;
  // do not parse prize descriptions such as 'Bs 500 + regalo'.
  if (!RegExp(r'^\d+(?:[.,]\d+)*$').hasMatch(amountText)) return value;

  if (RegExp(r'^\d{1,3}(?:[.,]\d{3})+$').hasMatch(amountText)) {
    amountText = amountText.replaceAll('.', '').replaceAll(',', '');
  } else {
    if (amountText.contains('.') && amountText.contains(',')) {
      return value;
    }
    amountText = amountText.replaceAll(',', '.');
  }
  final amount = double.tryParse(amountText);
  if (amount == null || !amount.isFinite) return value;
  // Currency comes from the trusted championship zone, not from user text.
  return expressMoney(amount, code);
}

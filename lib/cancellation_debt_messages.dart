/// User-facing copy for server-enforced cancellation-debt blocks.
///
/// Database exceptions can contain PostgreSQL/PostgREST diagnostics. Show only
/// the known debt amount and the next action; keep unrelated errors on their
/// existing handling path.
String? cancellationDebtActionMessage(
  Object? error, {
  required bool driver,
}) {
  final raw = error?.toString() ?? '';
  final normalized = raw.toLowerCase();
  if (!normalized.contains('deuda') ||
      !normalized.contains('cancelación')) {
    return null;
  }

  final money = RegExp(r'\b(CLP|BOB)\s*([0-9][0-9.,]*)',
          caseSensitive: false)
      .firstMatch(raw);
  final currency = money?.group(1)?.toUpperCase();
  final amount = money?.group(2)?.replaceFirst(RegExp(r'[.,]+$'), '');
  final due = currency == null || amount == null
      ? ''
      : ' de $currency $amount';
  final provider = currency == 'CLP'
      ? 'Mercado Pago'
      : currency == 'BOB'
          ? 'VeriPagos'
          : 'el QR de pago';
  final destination = driver
      ? 'antes de aceptar viajes'
      : 'antes de solicitar otro viaje';
  return 'Tienes una deuda pendiente por cancelación$due. Págala con '
      '$provider desde Pagos y billetera > Pagar deuda con QR $destination.';
}

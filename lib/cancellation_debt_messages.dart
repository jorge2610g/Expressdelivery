import 'package:flutter/material.dart';

/// Mensaje seguro para los bloqueos de deuda que devuelve el servidor. No
/// muestra códigos ni detalles SQL.
String? cancellationDebtActionMessage(Object? error, {required bool driver}) {
  final raw = error?.toString() ?? '';
  final normalized = raw.toLowerCase();
  final isCancellation =
      normalized.contains('cancelación') || normalized.contains('cancelacion');
  final isDebtLimit =
      normalized.contains('tope') ||
      normalized.contains('límite') ||
      normalized.contains('limite');
  final isWalletAdjustment =
      normalized.contains('ajuste') &&
      (normalized.contains('billetera') || normalized.contains('saldo'));
  if ((!normalized.contains('deuda') && !isWalletAdjustment) ||
      !(isCancellation || isDebtLimit || isWalletAdjustment)) {
    return null;
  }

  final money = RegExp(
    r'\b(?:(CLP|BOB)\s*([0-9][0-9.,]*)|([0-9][0-9.,]*)\s*(CLP|BOB))',
    caseSensitive: false,
  ).firstMatch(raw);
  final currency = (money?.group(1) ?? money?.group(4))?.toUpperCase();
  final amount = (money?.group(2) ?? money?.group(3))?.replaceFirst(
    RegExp(r'[.,]+$'),
    '',
  );
  final due = currency == null || amount == null ? '' : ' de $currency $amount';
  final debtLabel = isCancellation
      ? 'deuda pendiente por cancelación'
      : 'deuda pendiente en tu billetera';
  final action = driver
      ? 'Para volver a conectarte y aceptar viajes'
      : 'Para solicitar otro viaje';
  if (isDebtLimit) {
    return 'Tu deuda de billetera$due supera el tope permitido. $action, '
        'págala desde Pagos y billetera.';
  }
  return 'Tienes una $debtLabel$due. $action, págala desde Pagos y billetera.';
}

/// Muestra una tarjeta inferior de deuda. Devuelve null si el error no era
/// una deuda, true si eligió abrir la billetera y false si la cerró.
Future<bool?> showCancellationDebtBlock(
  BuildContext context,
  Object? error, {
  required bool driver,
}) async {
  final message = cancellationDebtActionMessage(error, driver: driver);
  if (message == null || !context.mounted) return null;

  final money = RegExp(
    r'\b(?:(CLP|BOB)\s*([0-9][0-9.,]*)|([0-9][0-9.,]*)\s*(CLP|BOB))',
    caseSensitive: false,
  ).firstMatch(error?.toString() ?? '');
  final currency = (money?.group(1) ?? money?.group(4))?.toUpperCase();
  final amount = (money?.group(2) ?? money?.group(3))?.replaceFirst(
    RegExp(r'[.,]+$'),
    '',
  );
  final moneyMatches = RegExp(
    r'\b(?:(CLP|BOB)\s*([0-9][0-9.,]*)|([0-9][0-9.,]*)\s*(CLP|BOB))',
    caseSensitive: false,
  ).allMatches(error?.toString() ?? '').toList();
  final secondMoney = moneyMatches.length > 1 ? moneyMatches[1] : null;
  final limitCurrency = (secondMoney?.group(1) ?? secondMoney?.group(4))
      ?.toUpperCase();
  final limitAmount = (secondMoney?.group(2) ?? secondMoney?.group(3))
      ?.replaceFirst(RegExp(r'[.,]+$'), '');
  final isCancellation = (error?.toString() ?? '').toLowerCase().contains(
    'cancel',
  );
  final isDebtLimit =
      (error?.toString() ?? '').toLowerCase().contains('tope') ||
      (error?.toString() ?? '').toLowerCase().contains('límite') ||
      (error?.toString() ?? '').toLowerCase().contains('limite');

  final shouldOpenWallet = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: MediaQuery.sizeOf(sheetContext).height * .86,
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        14 + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(sheetContext).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF98A2B3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFF155EEF),
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      isCancellation
                          ? 'Deuda por cancelación'
                          : 'Deuda de billetera',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isDebtLimit
                    ? 'Tu deuda supera el tope que permite tu zona. Paga desde tu billetera para volver a usar el servicio.'
                    : driver
                    ? 'Para conectarte y aceptar viajes, primero debes saldar esta deuda.'
                    : 'Para solicitar otro viaje, primero debes saldar esta deuda.',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF667085),
                ),
              ),
              if (currency != null && amount != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F8FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD6E4FF)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Monto pendiente',
                          style: TextStyle(
                            color: Color(0xFF475467),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '$currency $amount',
                        style: const TextStyle(
                          color: Color(0xFF155EEF),
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isDebtLimit &&
                  limitCurrency != null &&
                  limitAmount != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Tope permitido: $limitCurrency $limitAmount',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.wallet_rounded),
                label: const Text('Ir a Pagos y billetera'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('Ahora no'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return shouldOpenWallet ?? false;
}

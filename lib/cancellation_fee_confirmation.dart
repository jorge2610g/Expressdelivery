import 'package:flutter/material.dart';

import 'services/express_service.dart';

/// Displays the server-calculated fee before the user confirms cancellation.
/// The cancellation RPC compares this accepted fee against its transactional
/// quote and asks the user to review again if the zone rate changed.
Future<num?> confirmTripCancellationFee(
  BuildContext context,
  ExpressService service,
  String tripId,
) async {
  try {
    final quote = await service.cancellationFeeQuote(tripId);
    if (!context.mounted) return null;
    return await _confirmQuotedCancellationFee(context, quote);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo verificar el cobro de cancelación. Inténtalo otra vez.',
          ),
        ),
      );
    }
    return null;
  }
}

Future<num?> confirmRideRequestCancellationFee(
  BuildContext context,
  ExpressService service,
  String rideRequestId,
) async {
  try {
    final quote =
        await service.cancellationFeeQuoteForRideRequest(rideRequestId);
    if (!context.mounted) return null;
    return await _confirmQuotedCancellationFee(context, quote);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo verificar el cobro de cancelación. Inténtalo otra vez.',
          ),
        ),
      );
    }
    return null;
  }
}

Future<num?> _confirmQuotedCancellationFee(
  BuildContext context,
  Map<String, dynamic> quote,
) async {
  final fee = num.tryParse(quote['fee']?.toString() ?? '') ?? 0;
  if (fee <= 0) return 0;
  if (!context.mounted) return null;
  final seconds = int.tryParse(quote['grace_seconds']?.toString() ?? '') ?? 0;
  final remaining = seconds > 0
      ? ' Quedan ${(seconds ~/ 60)}:${(seconds % 60).toString().padLeft(2, '0')} para que termine el plazo de espera.'
      : '';
  return await showDialog<num>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Cancelar con cobro'),
          content: Text(
            'Se registrará una deuda de ${quote['currency'] ?? ''} ${_amount(fee)}.'
            '$remaining ¿Quieres continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Seguir esperando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, fee),
              child: const Text('Cancelar y aceptar el cobro'),
            ),
          ],
        ),
      );
}

String _amount(num value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

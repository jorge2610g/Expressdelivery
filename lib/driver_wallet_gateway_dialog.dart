import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/express_service.dart';

class DriverWalletGatewayDialog extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic> checkout;
  final FutureOr<void> Function() onApproved;
  const DriverWalletGatewayDialog({
    super.key,
    required this.service,
    required this.checkout,
    required this.onApproved,
  });
  @override
  State<DriverWalletGatewayDialog> createState() =>
      _DriverWalletGatewayDialogState();
}

class _DriverWalletGatewayDialogState
    extends State<DriverWalletGatewayDialog> with WidgetsBindingObserver {
  Timer? timer;
  bool checking = false;
  bool confirmed = false;
  String message = 'Esperando confirmación del proveedor.';

  String get id => widget.checkout['checkout_id']?.toString() ?? '';
  bool get mercadoPago => widget.checkout['provider'] == 'mercado_pago';
  bool get cancellationDebt =>
      widget.checkout['purpose'] == 'cancellation_debt';
  String get payUrl => widget.checkout['checkout_url']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_verify()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_verify()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_verify());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    if (checking || confirmed || id.isEmpty) return;
    setState(() => checking = true);
    try {
      final checked = await widget.service.checkDriverWalletGateway(id);
      if (!mounted) return;
      if (checked['approved'] == true) {
        timer?.cancel();
        confirmed = true;
        setState(() => message = cancellationDebt
            ? '¡Pago confirmado! La deuda de cancelación quedó pagada.'
            : '¡Pago confirmado! El saldo ya se acreditó en tu billetera.');
        await widget.onApproved();
        return;
      }
      final status = checked['status']?.toString() ?? 'pending';
      setState(() => message = status == 'failed'
          ? 'El pago fue rechazado o expiró. No se acreditó saldo.'
          : 'Pago pendiente. Express verificará el estado directamente '
            'en la pasarela.');
    } catch (_) {
      if (mounted) setState(() => message =
        'No se pudo verificar el pago. Intenta nuevamente; '
        'el saldo no se acreditará sin confirmación.');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _openCheckout() async {
    final uri = Uri.tryParse(payUrl);
    if (uri == null || uri.scheme != 'https') {
      setState(() => message = 'Mercado Pago no devolvió un enlace válido.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) setState(() => message =
        'No se pudo abrir Mercado Pago. Inténtalo de nuevo.');
  }

  Widget _qr() {
    final raw = widget.checkout['qr_payload']?.toString() ?? '';
    final payload = raw.contains(',')
        ? raw.substring(raw.indexOf(',') + 1)
        : raw;
    if (payload.isEmpty) return const Text('No se recibió el código QR.');
    try {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: Image.memory(
          base64Decode(payload.replaceAll('\n', '').replaceAll(' ', '')),
          width: 260,
          height: 260,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Text('No se pudo visualizar el código QR.'),
        ),
      );
    } catch (_) {
      return const Text('El proveedor devolvió un QR inválido.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.checkout['amount']?.toString() ?? '';
    final currency = widget.checkout['currency_code']?.toString() ?? '';
    return AlertDialog(
      title: Text(mercadoPago
          ? (cancellationDebt ? 'Deuda con Mercado Pago' : 'Recarga con Mercado Pago')
          : (cancellationDebt ? 'Deuda con VeriPagos' : 'Recarga con VeriPagos')),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!mercadoPago) _qr(),
            const SizedBox(height: 12),
            Text('$currency $amount',
              style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            if (mercadoPago && !confirmed)
              FilledButton.icon(
                onPressed: _openCheckout,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Pagar con Mercado Pago'),
              ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              cancellationDebt
                  ? 'La deuda se considera pagada solo cuando Express verifica la confirmación del proveedor.'
                  : 'Nunca se acreditará saldo solo por abrir el enlace o mostrar el QR. Debe confirmarlo el proveedor.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: checking ? null : () => Navigator.pop(context),
          child: Text(confirmed ? 'Finalizar' : 'Cerrar'),
        ),
        if (!confirmed)
          FilledButton.icon(
            onPressed: checking ? null : _verify,
            icon: checking
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            label: const Text('Verificar pago'),
          ),
      ],
    );
  }
}

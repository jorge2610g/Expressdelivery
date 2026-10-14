import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'money_format.dart';
import 'services/express_service.dart';

const _couponBlue = Color(0xFF1769E0);
const _couponInk = Color(0xFF152239);
const _couponBg = Color(0xFFF6F8FC);

/// Personal, channel-scoped coupon wallet. Redemption and pricing remain
/// authoritative in the existing checkout RPC: saving never applies a discount.
class DeliveryCustomerCouponsPage extends StatefulWidget {
  final ExpressService service;

  const DeliveryCustomerCouponsPage({super.key, required this.service});

  @override
  State<DeliveryCustomerCouponsPage> createState() =>
      _DeliveryCustomerCouponsPageState();
}

class _DeliveryCustomerCouponsPageState
    extends State<DeliveryCustomerCouponsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = widget.service.deliveryMyCoupons();
    });
  }

  String _discount(Map<String, dynamic> coupon) {
    final value = marketNumber(coupon['discount_value']);
    if (coupon['discount_type'] == 'percent') {
      return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}% de descuento';
    }
    final currency = coupon['currency_code']?.toString() ?? 'CLP';
    return marketMoney(value, currency) + ' de descuento';
  }

  Future<void> _saveCoupon() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Agregar un cupón'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Introduce el código que recibiste para guardarlo en tu cuenta.'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 64,
              decoration: const InputDecoration(
                labelText: 'Código del cupón',
                hintText: 'Ej.: EXPRESS10',
                prefixIcon: Icon(Icons.local_offer_outlined),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.of(dialogContext).pop(controller.text.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Guardar cupón'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || code == null || code.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final result = await widget.service.deliverySaveCoupon(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message']?.toString() ??
            (result['ok'] == true ? 'Cupón guardado.' : 'Cupón no disponible.')),
      ));
      if (result['ok'] == true) _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'No pudimos verificar el cupón. Comprueba tu conexión y vuelve a intentarlo.',
        )),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showHelp() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('¿Cómo uso un cupón?',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _helpRow(Icons.add_circle_outline_rounded,
                  'Guárdalo', 'Pulsa «Agregar nuevo cupón» y escribe el código.'),
              _helpRow(Icons.restaurant_rounded, 'Elige tu pedido',
                  'Selecciona un restaurante participante en tu zona.'),
              _helpRow(Icons.shopping_cart_checkout_rounded,
                  'Úsalo al pagar',
                  'Copia el código y colócalo en «Cupón» antes de confirmar el pedido.'),
              const SizedBox(height: 6),
              const Text(
                'Cada cupón tiene condiciones, fechas y límites de uso. '
                'El descuento definitivo se calcula en el resumen del pedido.',
                style: TextStyle(color: Color(0xFF667085), fontSize: 12),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpRow(IconData icon, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFFE8F1FF),
          child: Icon(icon, color: _couponBlue, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(body, style: const TextStyle(color: Color(0xFF667085))),
          ],
        )),
      ],
    ),
  );

  String _status(Map<String, dynamic> coupon) => switch (coupon['status']) {
    'available' => 'Disponible',
    'used' => 'Utilizado',
    'expired' => 'Vencido o agotado',
    'other_zone' => 'Disponible en otra zona',
    _ => 'No disponible',
  };

  Widget _couponCard(Map<String, dynamic> coupon) {
    final available = coupon['status'] == 'available';
    final code = coupon['code']?.toString() ?? '';
    final expires = DateTime.tryParse(coupon['ends_at']?.toString() ?? '');
    final date = expires == null ? '' :
        '${expires.toLocal().day.toString().padLeft(2, '0')}/'
        '${expires.toLocal().month.toString().padLeft(2, '0')}/'
        '${expires.toLocal().year}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                  color: available ? const Color(0xFFE8F1FF) : _couponBg,
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.confirmation_number_outlined,
                  color: available ? _couponBlue : const Color(0xFF98A2B3)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(coupon['title']?.toString() ?? 'Cupón Express',
                    style: const TextStyle(
                        color: _couponInk, fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 3),
                Text(_discount(coupon), style: const TextStyle(
                    color: _couponBlue, fontWeight: FontWeight.w800)),
              ],
            )),
            Text(_status(coupon), style: TextStyle(
                color: available ? const Color(0xFF067647) : const Color(0xFF667085),
                fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
          if ((coupon['description']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(coupon['description'].toString(),
                style: const TextStyle(color: Color(0xFF667085), fontSize: 13)),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code, style: const TextStyle(
                    fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                if (date.isNotEmpty)
                  Text('Hasta el $date',
                      style: const TextStyle(color: Color(0xFF667085), fontSize: 11)),
              ],
            )),
            TextButton.icon(
              onPressed: !available ? null : () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Código copiado. Úsalo al pagar tu pedido.')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('Copiar código'),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _couponBg,
      appBar: AppBar(
        title: const Text('Mis cupones', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        actions: [IconButton(
          tooltip: '¿Cómo uso un cupón?',
          onPressed: _showHelp,
          icon: const Icon(Icons.help_outline_rounded),
        )],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off_rounded, size: 46, color: _couponBlue),
                const SizedBox(height: 14),
                const Text('No pudimos cargar tus cupones.',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                FilledButton(onPressed: _refresh, child: const Text('Reintentar')),
              ]),
            ));
          }
          final all = snapshot.data ?? [];
          final available = all.where((e) => e['status'] == 'available').toList();
          final history = all.where((e) => e['status'] != 'available').toList();
          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(23),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(27),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0B57D0), Color(0xFF398BFF)],
                    ),
                  ),
                  child: Row(children: [
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MIS CUPONES', style: TextStyle(
                            color: Color(0xFFCDE5FF), letterSpacing: 1.5,
                            fontSize: 11, fontWeight: FontWeight.w900)),
                        SizedBox(height: 10),
                        Text('Más descuentos para tus pedidos',
                            style: TextStyle(color: Colors.white, fontSize: 23,
                                height: 1.15, fontWeight: FontWeight.w900)),
                        SizedBox(height: 10),
                        Text('Guarda tus códigos y ahorra en Express Delivery.',
                            style: TextStyle(color: Color(0xFFEBF4FF), fontSize: 13)),
                      ],
                    )),
                    const SizedBox(width: 8),
                    const Icon(Icons.confirmation_number_rounded,
                        color: Color(0xFFFFD46E), size: 76),
                  ]),
                ),
                const SizedBox(height: 20),
                if (all.isEmpty) ...[
                  const SizedBox(height: 60),
                  const Center(child: Icon(Icons.local_offer_outlined,
                      size: 100, color: Color(0xFFA8B9D6))),
                  const SizedBox(height: 22),
                  const Text('¿Tienes un cupón nuevo?',
                      textAlign: TextAlign.center, style: TextStyle(
                          fontSize: 23, fontWeight: FontWeight.w900,
                          color: _couponInk)),
                  const SizedBox(height: 8),
                  const Text('Ingresa el código aquí y úsalo cuando quieras.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF667085), fontSize: 14)),
                ] else ...[
                  Text('Disponibles (${available.length})',
                      style: const TextStyle(
                          color: _couponInk, fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  if (available.isEmpty) const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No tienes cupones disponibles por ahora.',
                        style: TextStyle(color: Color(0xFF667085))),
                  ),
                  ...available.map(_couponCard),
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('Historial',
                        style: TextStyle(color: _couponInk, fontSize: 19,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    ...history.map(_couponCard),
                  ],
                ],
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: double.infinity, height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveCoupon,
                icon: const Icon(Icons.add_rounded),
                label: Text(_saving ? 'Guardando…' : 'Agregar nuevo cupón'),
                style: FilledButton.styleFrom(backgroundColor: _couponBlue),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, height: 46,
              child: OutlinedButton.icon(
                onPressed: _showHelp,
                icon: const Icon(Icons.help_outline_rounded),
                label: const Text('¿Cómo uso un cupón?'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

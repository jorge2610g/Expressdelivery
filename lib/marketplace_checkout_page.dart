import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/runtime_channel.dart';

import 'location_service.dart';
import 'location_picker.dart';
import 'services/express_service.dart';

double marketNumber(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String marketMoney(Object? value, String currency) {
  final amount = marketNumber(value);
  final code = currency.toUpperCase();
  if (code == 'CLP') {
    final raw = amount.round().toString();
    final grouped = raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return 'CLP ' + grouped;
  }
  if (code == 'BOB') {
    final shown = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return 'Bs ' + shown;
  }
  return code + ' ' + amount.toStringAsFixed(2);
}

double marketDistanceKm(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const earth = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

class MarketplaceCheckoutPage extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic> merchant;
  final List<Map<String, dynamic>> products;
  final Map<String, int> cart;

  const MarketplaceCheckoutPage({
    super.key,
    required this.service,
    required this.merchant,
    required this.products,
    required this.cart,
  });

  @override
  State<MarketplaceCheckoutPage> createState() =>
      _MarketplaceCheckoutPageState();
}

class _MarketplaceCheckoutPageState extends State<MarketplaceCheckoutPage> {
  static const blue = Color(0xFF1769E0);
  static const ink = Color(0xFF101828);
  static const muted = Color(0xFF667085);

  final address = TextEditingController(text: 'Mi ubicación actual');
  final note = TextEditingController();

  Map<String, dynamic>? quote;
  bool loading = true;
  bool placing = false;
  bool priority = false;
  double tip = 0;
  String paymentMethod = 'cash';
  double distanceKm = 0;
  double? dropoffLat;
  double? dropoffLng;
  String? error;

  List<Map<String, dynamic>> get items => widget.cart.entries
      .map(
        (entry) => <String, dynamic>{
          'product_id': entry.key,
          'quantity': entry.value,
        },
      )
      .toList();

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    address.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final position = await const ExpressLocationService().currentPosition();
      dropoffLat = position.latitude;
      dropoffLng = position.longitude;

      final merchantLat = marketNumber(widget.merchant['latitude']);
      final merchantLng = marketNumber(widget.merchant['longitude']);
      if (merchantLat != 0 && merchantLng != 0) {
        distanceKm = marketDistanceKm(
          merchantLat,
          merchantLng,
          position.latitude,
          position.longitude,
        );
      }

      await _refreshQuote();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = ExpressRuntimeChannel.userSafeError(
          e,
          fallback: 'No pudimos actualizar el pedido.',
        );
        loading = false;
      });
    }
  }


  Future<void> _pickDeliveryLocation() async {
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: 'Dirección de entrega',
          initialLabel: address.text.trim().isEmpty
              ? 'Mi ubicación actual'
              : address.text.trim(),
          initialLatitude: dropoffLat,
          initialLongitude: dropoffLng,
        ),
      ),
    );

    if (!mounted || picked == null) return;

    final merchantLat = marketNumber(widget.merchant['latitude']);
    final merchantLng = marketNumber(widget.merchant['longitude']);
    var nextDistance = 0.0;
    if (merchantLat != 0 && merchantLng != 0) {
      nextDistance = marketDistanceKm(
        merchantLat,
        merchantLng,
        picked.latitude,
        picked.longitude,
      );
    }

    setState(() {
      address.text = picked.label;
      dropoffLat = picked.latitude;
      dropoffLng = picked.longitude;
      distanceKm = nextDistance;
    });

    await _refreshQuote();
  }

  Future<void> _refreshQuote() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final value = await widget.service.marketplaceQuote(
        merchantId: widget.merchant['id'].toString(),
        items: items,
        distanceKm: distanceKm,
        tip: tip,
        priority: priority,
      );
      if (!mounted) return;

      setState(() {
        quote = value;
        loading = false;

        if (paymentMethod == 'transfer' &&
            value['transfer_enabled'] != true) {
          paymentMethod = value['cash_enabled'] == true
              ? 'cash'
              : 'transfer';
        }
        if (paymentMethod == 'cash' && value['cash_enabled'] != true) {
          paymentMethod = 'transfer';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = ExpressRuntimeChannel.userSafeError(
          e,
          fallback: 'No pudimos actualizar el pedido.',
        );
        loading = false;
      });
    }
  }

  Future<void> _placeOrder() async {
    if (placing || quote == null) return;

    if (address.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe la dirección de entrega.')),
      );
      return;
    }

    setState(() => placing = true);

    try {
      final result = await widget.service.marketplaceCreateOrder(
        merchantId: widget.merchant['id'].toString(),
        items: items,
        paymentMethod: paymentMethod,
        dropoffAddress: address.text.trim(),
        dropoffLatitude: dropoffLat,
        dropoffLongitude: dropoffLng,
        distanceKm: distanceKm,
        tip: tip,
        priority: priority,
        customerNote:
            note.text.trim().isEmpty ? null : note.text.trim(),
      );

      final order = result['order'] is Map
          ? Map<String, dynamic>.from(result['order'] as Map)
          : <String, dynamic>{};
      final orderId = order['id']?.toString();

      if (orderId == null || orderId.isEmpty) {
        throw StateError('El pedido no devolvió identificador.');
      }

      if (!mounted) return;

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MarketplaceOrderPage(
            service: widget.service,
            orderId: orderId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ExpressRuntimeChannel.userSafeError(
              e,
              fallback: 'No se pudo crear el pedido. Intenta nuevamente.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => placing = false);
    }
  }

  Widget _moneyRow(
    String label,
    Object? amount,
    String currency, {
    bool strong = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color ?? muted,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            marketMoney(amount, currency),
            style: TextStyle(
              color: color ?? ink,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentTile({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
  }) {
    return RadioListTile<String>(
      value: value,
      groupValue: paymentMethod,
      onChanged: enabled
          ? (next) {
              if (next != null) setState(() => paymentMethod = next);
            }
          : null,
      secondary: Icon(icon, color: enabled ? blue : Colors.grey),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(subtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = quote ?? const <String, dynamic>{};
    final currency = q['currency_code']?.toString() ??
        widget.merchant['currency_code']?.toString() ??
        'CLP';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text(
          'Finalizar pedido',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(14),
        child: FilledButton.icon(
          onPressed: placing || loading || quote == null ? null : _placeOrder,
          icon: placing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_rounded),
          label: Text(
            quote == null
                ? 'Calculando…'
                : 'Confirmar · ' +
                    marketMoney(q['total_amount'], currency),
          ),
        ),
      ),
      body: loading && quote == null
          ? const Center(child: CircularProgressIndicator())
          : error != null && quote == null
              ? Center(
                  child: FilledButton.icon(
                    onPressed: _bootstrap,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.merchant['name']?.toString() ??
                                'Comercio',
                            style: const TextStyle(
                              color: ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            distanceKm > 0
                                ? distanceKm.toStringAsFixed(1) +
                                    ' km hasta tu ubicación'
                                : 'La tarifa por distancia se calculará con los datos disponibles.',
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: address,
                      readOnly: true,
                      onTap: _pickDeliveryLocation,
                      decoration: InputDecoration(
                        labelText: 'Dirección de entrega',
                        prefixIcon:
                            const Icon(Icons.location_on_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Elegir en el mapa',
                          onPressed: _pickDeliveryLocation,
                          icon: const Icon(Icons.map_outlined),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        distanceKm <= 0
                            ? 'Selecciona el punto exacto de entrega.'
                            : 'Distancia estimada: ' +
                                distanceKm.toStringAsFixed(1) +
                                ' km',
                        style: const TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: note,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Nota para el comercio / repartidor',
                        prefixIcon: Icon(Icons.notes_rounded),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Propina',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final value in <double>[
                          0,
                          currency == 'CLP' ? 500 : 2,
                          currency == 'CLP' ? 1000 : 5,
                          currency == 'CLP' ? 2000 : 10,
                        ])
                          ChoiceChip(
                            label: Text(
                              value == 0
                                  ? 'Sin propina'
                                  : marketMoney(value, currency),
                            ),
                            selected: tip == value,
                            onSelected: q['tips_enabled'] == true
                                ? (_) {
                                    setState(() => tip = value);
                                    unawaited(_refreshQuote());
                                  }
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: priority,
                      onChanged: q['priority_enabled'] == true
                          ? (value) {
                              setState(() => priority = value);
                              unawaited(_refreshQuote());
                            }
                          : null,
                      title: const Text(
                        'Envío Plus · prioridad',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        q['priority_enabled'] == true
                            ? marketNumber(
                                      q['plus_priority_deliveries_remaining'],
                                    ) >
                                    0
                                ? 'Express Plus incluye prioridad sin recargo. Al confirmar se consumirá 1 de tus envíos prioritarios incluidos.'
                                : 'Tu pedido entra con prioridad en el despacho para intentar llegar antes.'
                            : 'No disponible en esta zona.',
                      ),
                      secondary: const Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFFFFA000),
                      ),
                    ),
                    if (q['plus_subscription_applied'] == true)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF7EE),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          q['plus_priority_included_applied'] == true
                              ? 'Express Plus aplicado: prioridad incluida sin recargo. Te quedarán ' +
                                  (q['plus_priority_deliveries_remaining_after_order'] ??
                                          0)
                                      .toString() +
                                  ' envíos prioritarios.'
                              : q['plus_free_delivery_applied'] == true
                                  ? 'Express Plus aplicado: envío gratis.'
                                  : 'Express Plus aplicado a este pedido.',
                          style: const TextStyle(
                            color: Color(0xFF14804A),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    const Text(
                      'Método de pago',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          _paymentTile(
                            value: 'transfer',
                            icon: Icons.account_balance_rounded,
                            title: 'Transferencia',
                            subtitle:
                                'El comercio confirma tu comprobante dentro del pedido.',
                            enabled: q['transfer_enabled'] == true,
                          ),
                          const Divider(height: 1),
                          _paymentTile(
                            value: 'cash',
                            icon: Icons.payments_outlined,
                            title: 'Efectivo',
                            subtitle:
                                'El repartidor cobra el total, pero su ganancia queda separada.',
                            enabled: q['cash_enabled'] == true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          _moneyRow(
                            'Productos',
                            q['subtotal'],
                            currency,
                          ),
                          if (marketNumber(q['product_discount']) > 0)
                            _moneyRow(
                              'Descuento Express Plus',
                              -marketNumber(q['product_discount']),
                              currency,
                              color: const Color(0xFF14804A),
                            ),
                          _moneyRow(
                            'Costo de servicio / envío',
                            q['customer_delivery_fee'],
                            currency,
                          ),
                          if (marketNumber(q['priority_fee']) > 0)
                            _moneyRow(
                              'Envío Plus',
                              q['priority_fee'],
                              currency,
                            ),
                          if (marketNumber(q['tip_amount']) > 0)
                            _moneyRow(
                              'Propina',
                              q['tip_amount'],
                              currency,
                            ),
                          const Divider(),
                          _moneyRow(
                            'Total',
                            q['total_amount'],
                            currency,
                            strong: true,
                            color: blue,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'La tarifa del repartidor se calcula de forma independiente. El comercio conserva el valor de los productos; el costo de servicio lo paga el cliente.',
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
    );
  }
}

class MarketplaceOrderPage extends StatefulWidget {
  final ExpressService service;
  final String orderId;

  const MarketplaceOrderPage({
    super.key,
    required this.service,
    required this.orderId,
  });

  @override
  State<MarketplaceOrderPage> createState() =>
      _MarketplaceOrderPageState();
}

class _MarketplaceOrderPageState extends State<MarketplaceOrderPage> {
  final message = TextEditingController();
  final receipt = TextEditingController();
  late Future<Map<String, dynamic>> future;
  Timer? timer;
  bool sending = false;
  bool verifying = false;

  @override
  void initState() {
    super.initState();
    future = widget.service.marketplaceOrderDetail(widget.orderId);
    timer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_reload()),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    message.dispose();
    receipt.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      future = widget.service.marketplaceOrderDetail(widget.orderId);
    });
  }

  Future<void> _send({bool receiptMode = false}) async {
    final controller = receiptMode ? receipt : message;
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;

    setState(() => sending = true);
    try {
      await widget.service.marketplaceSendOrderMessage(
        orderId: widget.orderId,
        body: text,
        messageType: receiptMode ? 'receipt' : 'text',
      );
      controller.clear();
      await _reload();
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _verifyPayment() async {
    if (verifying) return;

    setState(() => verifying = true);
    try {
      final result =
          await widget.service.marketplaceVerifyOnlinePayment(widget.orderId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['approved'] == true
                ? 'Pago confirmado por Mercado Pago.'
                : 'Estado de pago: ' +
                    (result['status']?.toString() ?? 'pendiente'),
          ),
        ),
      );

      await _reload();
    } finally {
      if (mounted) setState(() => verifying = false);
    }
  }

  int _orderProgress(String status) {
    switch (status) {
      case 'pending':
      case 'awaiting_transfer':
      case 'payment_review':
        return 0;
      case 'confirmed':
      case 'preparing':
        return 1;
      case 'ready':
      case 'searching_driver':
      case 'driver_assigned':
        return 2;
      case 'picked_up':
      case 'delivering':
        return 3;
      case 'delivered':
        return 4;
      case 'cancelled':
        return -1;
      default:
        return 0;
    }
  }

  String _orderTitle(String status) {
    switch (status) {
      case 'awaiting_transfer':
        return 'Esperando tu transferencia';
      case 'payment_review':
        return 'Verificando tu pago';
      case 'confirmed':
        return 'Pedido confirmado';
      case 'preparing':
        return 'Tu pedido se está preparando';
      case 'ready':
        return 'Tu pedido está listo';
      case 'searching_driver':
        return 'Buscando repartidor';
      case 'driver_assigned':
        return 'Repartidor asignado';
      case 'picked_up':
        return 'El repartidor retiró tu pedido';
      case 'delivering':
        return 'Pedido en camino';
      case 'delivered':
        return 'Pedido entregado';
      case 'cancelled':
        return 'Pedido cancelado';
      default:
        return 'Pedido recibido';
    }
  }

  String _orderSubtitle(String status) {
    switch (status) {
      case 'awaiting_transfer':
        return 'Completa la transferencia y envía la referencia para que el comercio pueda revisarla.';
      case 'payment_review':
        return 'El comercio está revisando tu comprobante.';
      case 'confirmed':
        return 'El comercio recibió y confirmó tu pedido.';
      case 'preparing':
        return 'El local está preparando tus productos.';
      case 'ready':
        return 'El pedido está listo para ser retirado.';
      case 'searching_driver':
        return 'Estamos buscando un repartidor disponible cerca del local.';
      case 'driver_assigned':
        return 'Ya asignamos un repartidor para retirar tu pedido.';
      case 'picked_up':
        return 'Tu pedido salió del local.';
      case 'delivering':
        return 'Sigue el estado mientras el repartidor va hacia tu dirección.';
      case 'delivered':
        return 'La entrega fue completada.';
      case 'cancelled':
        return 'Este pedido ya no continuará.';
      default:
        return 'Recibimos tu pedido. Te avisaremos cuando el comercio lo confirme.';
    }
  }

  Widget _trackingCard(
    Map<String, dynamic> order,
    Map<String, dynamic> merchant,
    String currency,
  ) {
    final status = order['status']?.toString() ?? 'pending';
    final progress = _orderProgress(status);
    final cancelled = status == 'cancelled';
    final etaMin = merchant['eta_min_minutes'] ?? 15;
    final etaMax = merchant['eta_max_minutes'] ?? 40;
    const labels = <String>[
      'Pedido',
      'Preparando',
      'Repartidor',
      'En camino',
      'Entregado',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: cancelled
                    ? const Color(0xFFFEE4E2)
                    : const Color(0xFFEAF2FF),
                child: Icon(
                  cancelled
                      ? Icons.close_rounded
                      : status == 'delivered'
                          ? Icons.check_rounded
                          : Icons.delivery_dining_rounded,
                  color: cancelled
                      ? const Color(0xFFD92D20)
                      : const Color(0xFF1769E0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _orderTitle(status),
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _orderSubtitle(status),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!cancelled && status != 'delivered') ...[
            const SizedBox(height: 12),
            Text(
              'Llegada estimada: $etaMin-$etaMax min',
              style: const TextStyle(
                color: Color(0xFF1769E0),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (cancelled)
            const LinearProgressIndicator(
              value: 1,
              color: Color(0xFFD92D20),
              backgroundColor: Color(0xFFFEE4E2),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 27,
                          height: 27,
                          decoration: BoxDecoration(
                            color: i <= progress
                                ? const Color(0xFF1769E0)
                                : const Color(0xFFE4E7EC),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            i < progress || status == 'delivered'
                                ? Icons.check_rounded
                                : i == progress
                                    ? Icons.circle
                                    : Icons.circle_outlined,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          labels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: i <= progress
                                ? const Color(0xFF101828)
                                : const Color(0xFF98A2B3),
                            fontSize: 9,
                            fontWeight: i <= progress
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pago: ' +
                      (order['payment_status']?.toString() ?? 'pendiente'),
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                marketMoney(order['total_amount'], currency),
                style: const TextStyle(
                  color: Color(0xFF1769E0),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (order['is_priority'] == true) ...[
            const SizedBox(height: 8),
            const Chip(
              avatar: Icon(Icons.bolt_rounded, size: 18),
              label: Text('Envío Plus · prioridad'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemsCard(
    List<Map<String, dynamic>> items,
    String currency,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tu pedido',
            style: TextStyle(
              color: Color(0xFF101828),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Text(
                    (item['quantity'] ?? 1).toString() + '×',
                    style: const TextStyle(
                      color: Color(0xFF1769E0),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item['product_name']?.toString() ?? 'Producto',
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    marketMoney(item['line_total'], currency),
                    style: const TextStyle(
                      color: Color(0xFF101828),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};

        final order = data['order'] is Map
            ? Map<String, dynamic>.from(data['order'] as Map)
            : <String, dynamic>{};
        final merchant = data['merchant'] is Map
            ? Map<String, dynamic>.from(data['merchant'] as Map)
            : <String, dynamic>{};
        final messages = data['messages'] is List
            ? (data['messages'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];
        final items = data['items'] is List
            ? (data['items'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];

        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final currency = order['currency_code']?.toString() ?? 'CLP';
        final transfer = order['payment_method'] == 'transfer';
        final online = order['payment_method'] == 'mercado_pago';

        return Scaffold(
          backgroundColor: const Color(0xFFF6F8FC),
          appBar: AppBar(
            title: Text(
              'Pedido · ' +
                  (merchant['name']?.toString() ?? 'Express Delivery'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              IconButton(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _trackingCard(order, merchant, currency),
              const SizedBox(height: 12),
              _itemsCard(items, currency),
              if (items.isNotEmpty) const SizedBox(height: 12),
              if (online && order['payment_status'] != 'paid') ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: verifying ? null : _verifyPayment,
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('Verificar pago Mercado Pago'),
                ),
                if ((order['online_checkout_url']?.toString() ?? '')
                    .isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(
                        order['online_checkout_url'].toString(),
                      );
                      if (uri != null) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Volver al pago'),
                  ),
              ],
              if (transfer) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    (merchant['transfer_instructions']
                                    ?.toString()
                                    .trim()
                                    .isNotEmpty ??
                                false)
                        ? merchant['transfer_instructions'].toString()
                        : 'El comercio puede enviarte sus datos bancarios por este chat. Después envía la referencia o comprobante para revisión.',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: receipt,
                  decoration: InputDecoration(
                    labelText:
                        'Referencia / comprobante de transferencia',
                    suffixIcon: IconButton(
                      tooltip: 'Enviar a revisión',
                      onPressed:
                          sending ? null : () => _send(receiptMode: true),
                      icon: const Icon(Icons.receipt_long_rounded),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'Chat del pedido',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              if (messages.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Todavía no hay mensajes.'),
                  ),
                )
              else
                ...messages.map(
                  (row) => Card(
                    child: ListTile(
                      leading: Icon(
                        row['sender_role'] == 'customer'
                            ? Icons.person_outline_rounded
                            : row['sender_role'] == 'system'
                                ? Icons.info_outline_rounded
                                : Icons.storefront_rounded,
                      ),
                      title: Text(
                        row['body']?.toString() ??
                            row['attachment_url']?.toString() ??
                            '',
                      ),
                      subtitle: Text(
                        row['message_type']?.toString() ?? 'mensaje',
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: message,
                decoration: InputDecoration(
                  hintText: 'Escribe al comercio…',
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    onPressed: sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MarketplaceOrdersPage extends StatefulWidget {
  final ExpressService service;

  const MarketplaceOrdersPage({
    super.key,
    required this.service,
  });

  @override
  State<MarketplaceOrdersPage> createState() =>
      _MarketplaceOrdersPageState();
}

class _MarketplaceOrdersPageState extends State<MarketplaceOrdersPage> {
  late Future<List<Map<String, dynamic>>> future;

  @override
  void initState() {
    super.initState();
    future = widget.service.marketplaceMyOrders();
  }

  void _refresh() {
    setState(() => future = widget.service.marketplaceMyOrders());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis pedidos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rows = snapshot.data ?? const <Map<String, dynamic>>[];

          if (rows.isEmpty) {
            return const Center(
              child: Text('Todavía no tienes pedidos.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              final currency =
                  row['currency_code']?.toString() ?? 'CLP';

              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.delivery_dining_rounded),
                  ),
                  title: Text(
                    row['merchant_name']?.toString() ??
                        'Express Delivery',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    (row['status']?.toString() ?? 'pendiente') +
                        ' · ' +
                        (row['payment_method']?.toString() ?? ''),
                  ),
                  trailing: Text(
                    marketMoney(row['total_amount'], currency),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MarketplaceOrderPage(
                        service: widget.service,
                        orderId: row['id'].toString(),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ExpressPlusPage extends StatefulWidget {
  final ExpressService service;

  const ExpressPlusPage({
    super.key,
    required this.service,
  });

  @override
  State<ExpressPlusPage> createState() => _ExpressPlusPageState();
}

class _ExpressPlusPageState extends State<ExpressPlusPage> {
  late Future<Map<String, dynamic>> future;
  bool paying = false;

  @override
  void initState() {
    super.initState();
    future = widget.service.marketplacePlusState();
  }

  void _refresh() {
    setState(() => future = widget.service.marketplacePlusState());
  }

  Future<void> _buy(Map<String, dynamic> plan) async {
    if (paying) return;
    setState(() => paying = true);

    try {
      final payment = await widget.service.marketplaceCreatePlusPayment(
        plan['id'].toString(),
      );

      if (payment['ok'] != true) {
        throw StateError(
          payment['error']?.toString() ??
              'No se pudo iniciar el pago.',
        );
      }

      final checkout = payment['checkout_url']?.toString();
      final paymentId = payment['payment_id']?.toString();

      if (checkout != null && checkout.isNotEmpty) {
        final uri = Uri.tryParse(checkout);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      if (!mounted || paymentId == null) return;

      final approved = await showDialog<bool>(
        context: context,
        builder: (_) => _PlusPaymentDialog(
          service: widget.service,
          paymentId: paymentId,
        ),
      );

      if (approved == true && mounted) _refresh();
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text(
          'Express Plus',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data ?? const <String, dynamic>{};

          final subscription = data['subscription'] is Map
              ? Map<String, dynamic>.from(
                  data['subscription'] as Map,
                )
              : null;

          final plans = data['plans'] is List
              ? (data['plans'] as List)
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList()
              : <Map<String, dynamic>>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0B57D0),
                      Color(0xFF1769E0),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Express Plus',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Beneficios mensuales: envío gratis, descuentos exclusivos y promociones en locales participantes.',
                      style: TextStyle(
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (subscription != null) ...[
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.verified_rounded),
                    title: Text(
                      subscription['plan_name']?.toString() ??
                          'Plan activo',
                    ),
                    subtitle: Text(
                      'Activo hasta ' +
                          (subscription['expires_at']?.toString() ?? '') +
                          (marketNumber(
                                    subscription['included_priority_deliveries'],
                                  ) >
                                  0
                              ? '\nPrioritarios disponibles: ' +
                                  (subscription['priority_deliveries_remaining'] ??
                                          0)
                                      .toString()
                              : ''),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (plans.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      ExpressRuntimeChannel.technicalOr(
                        production:
                            'Express Plus no tiene planes disponibles por ahora.',
                        preview:
                            'Express Plus todavía no tiene un plan activo para esta zona. Administración puede configurarlo desde el panel.',
                      ),
                    ),
                  ),
                )
              else
                ...plans.map(
                  (plan) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan['name']?.toString() ??
                                'Express Plus',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            plan['description']?.toString() ?? '',
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              if (plan['free_delivery'] == true)
                                const Chip(
                                  label: Text('Envío gratis'),
                                ),
                              if (marketNumber(
                                    plan['included_priority_deliveries'],
                                  ) >
                                  0)
                                Chip(
                                  label: Text(
                                    plan['included_priority_deliveries']
                                            .toString() +
                                        ' envíos prioritarios incluidos',
                                  ),
                                ),
                              if (marketNumber(
                                    plan['default_discount_percent'],
                                  ) >
                                  0)
                                Chip(
                                  label: Text(
                                    plan['default_discount_percent']
                                            .toString() +
                                        '% descuento',
                                  ),
                                ),
                              const Chip(
                                label: Text('Promos exclusivas'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed:
                                  paying ? null : () => _buy(plan),
                              child: Text(
                                'Suscribirme · ' +
                                    marketMoney(
                                      plan['monthly_price'],
                                      plan['currency_code']
                                              ?.toString() ??
                                          'CLP',
                                    ) +
                                    ' / mes',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PlusPaymentDialog extends StatefulWidget {
  final ExpressService service;
  final String paymentId;

  const _PlusPaymentDialog({
    required this.service,
    required this.paymentId,
  });

  @override
  State<_PlusPaymentDialog> createState() =>
      _PlusPaymentDialogState();
}

class _PlusPaymentDialogState extends State<_PlusPaymentDialog> {
  Timer? timer;
  bool checking = false;
  String status = 'Esperando confirmación de Mercado Pago…';

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(_verify()),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    if (checking) return;

    setState(() => checking = true);

    try {
      final result =
          await widget.service.marketplaceVerifyPlusPayment(
        widget.paymentId,
      );

      if (!mounted) return;

      if (result['approved'] == true) {
        timer?.cancel();
        setState(() => status = 'Express Plus activado.');
        await Future<void>.delayed(
          const Duration(milliseconds: 600),
        );
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(
          () => status =
              'Estado: ' +
              (result['status']?.toString() ?? 'pendiente'),
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Activar Express Plus'),
      content: Text(status),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: checking ? null : _verify,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Verificar'),
        ),
      ],
    );
  }
}

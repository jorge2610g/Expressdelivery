import 'package:flutter/material.dart';

import 'core/runtime_channel.dart';
import 'services/express_service.dart';

double _merchantNumber(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _merchantMoney(Object? value, String currency) {
  final amount = _merchantNumber(value);
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

class MarketplaceMerchantPanelPage extends StatefulWidget {
  final ExpressService service;
  final List<Map<String, dynamic>> access;

  const MarketplaceMerchantPanelPage({
    super.key,
    required this.service,
    required this.access,
  });

  @override
  State<MarketplaceMerchantPanelPage> createState() =>
      _MarketplaceMerchantPanelPageState();
}

class _MarketplaceMerchantPanelPageState
    extends State<MarketplaceMerchantPanelPage> {
  String? merchantId;
  late Future<List<Map<String, dynamic>>> future;

  @override
  void initState() {
    super.initState();
    merchantId = widget.access.isEmpty
        ? null
        : widget.access.first['merchant_id']?.toString();
    future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final id = merchantId;
    if (id == null) return const [];
    return widget.service.marketplaceMerchantOrders(id);
  }

  void _refresh() {
    setState(() => future = _load());
  }

  Map<String, dynamic>? get currentMerchant {
    for (final row in widget.access) {
      if (row['merchant_id']?.toString() == merchantId) return row;
    }
    return null;
  }

  Future<void> _openOrder(String orderId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarketplaceMerchantOrderPage(
          service: widget.service,
          orderId: orderId,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.access.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('No tienes comercios vinculados a esta cuenta.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text(
          'Panel del comercio',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.access.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: merchantId,
                decoration: const InputDecoration(
                  labelText: 'Comercio',
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: widget.access
                    .map(
                      (row) => DropdownMenuItem<String>(
                        value: row['merchant_id']?.toString(),
                        child: Text(
                          row['merchant_name']?.toString() ?? 'Comercio',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    merchantId = value;
                    future = _load();
                  });
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  currentMerchant?['merchant_name']?.toString() ??
                      'Comercio',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData &&
                    snapshot.connectionState ==
                        ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        ExpressRuntimeChannel.userSafeError(
                          snapshot.error,
                          fallback: 'No se pudieron cargar los pedidos.',
                        ),
                      ),
                    ),
                  );
                }

                final rows =
                    snapshot.data ?? const <Map<String, dynamic>>[];

                if (rows.isEmpty) {
                  return const Center(
                    child: Text('Todavía no hay pedidos.'),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final currency =
                          row['currency_code']?.toString() ?? 'CLP';
                      final payment =
                          row['payment_method']?.toString() ?? '';
                      final status =
                          row['status']?.toString() ?? 'pendiente';

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              payment == 'transfer'
                                  ? Icons.account_balance_rounded
                                  : payment == 'cash'
                                      ? Icons.payments_outlined
                                      : Icons.credit_card_rounded,
                            ),
                          ),
                          title: Text(
                            row['customer_name']?.toString() ??
                                'Cliente Express',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Text(
                            status +
                                ' · ' +
                                payment +
                                ' · pago ' +
                                (row['payment_status']?.toString() ??
                                    'pendiente'),
                          ),
                          trailing: Text(
                            _merchantMoney(
                              row['total_amount'],
                              currency,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          onTap: () => _openOrder(
                            row['id'].toString(),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MarketplaceMerchantOrderPage extends StatefulWidget {
  final ExpressService service;
  final String orderId;

  const MarketplaceMerchantOrderPage({
    super.key,
    required this.service,
    required this.orderId,
  });

  @override
  State<MarketplaceMerchantOrderPage> createState() =>
      _MarketplaceMerchantOrderPageState();
}

class _MarketplaceMerchantOrderPageState
    extends State<MarketplaceMerchantOrderPage> {
  final message = TextEditingController();
  late Future<Map<String, dynamic>> future;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    future = widget.service.marketplaceOrderDetail(widget.orderId);
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      future = widget.service.marketplaceOrderDetail(widget.orderId);
    });
  }

  Future<void> _action(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await task();
      if (mounted) _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _setStatus(String status) async {
    await _action(() async {
      await widget.service.marketplaceSetOrderStatus(
        orderId: widget.orderId,
        status: status,
      );
    });
  }

  Future<void> _review(bool approve) async {
    await _action(() async {
      await widget.service.marketplaceReviewTransfer(
        orderId: widget.orderId,
        approve: approve,
        note: approve
            ? 'Transferencia aprobada por el comercio.'
            : 'Comprobante rechazado. Envía uno nuevo.',
      );
    });
  }

  Future<void> _markDriverPaid() async {
    await _action(() async {
      await widget.service.marketplaceMarkDriverPaid(
        widget.orderId,
        note:
            'El comercio confirmó el pago de tarifa y propina al repartidor.',
      );
    });
  }

  Future<void> _settle(
    String balanceKey,
    String label,
  ) async {
    await _action(() async {
      await widget.service.marketplaceSettleBalance(
        orderId: widget.orderId,
        balanceKey: balanceKey,
        note: 'Liquidación confirmada: ' + label + '.',
      );
    });
  }

  Future<void> _send() async {
    final text = message.text.trim();
    if (text.isEmpty) return;

    await _action(() async {
      await widget.service.marketplaceSendOrderMessage(
        orderId: widget.orderId,
        body: text,
        messageType: 'text',
      );
      message.clear();
    });
  }

  Widget _moneyLine(
    String label,
    Object? value,
    String currency, {
    bool strong = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _merchantMoney(value, currency),
            style: TextStyle(
              fontWeight:
                  strong ? FontWeight.w900 : FontWeight.w700,
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
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final order = data['order'] is Map
            ? Map<String, dynamic>.from(data['order'] as Map)
            : <String, dynamic>{};
        final financials = data['financials'] is Map
            ? Map<String, dynamic>.from(data['financials'] as Map)
            : <String, dynamic>{};
        final messages = data['messages'] is List
            ? (data['messages'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];

        final status = order['status']?.toString() ?? '';
        final paymentStatus =
            order['payment_status']?.toString() ?? '';
        final paymentMethod =
            order['payment_method']?.toString() ?? '';
        final currency =
            order['currency_code']?.toString() ?? 'CLP';

        final transferReview =
            paymentMethod == 'transfer' &&
            paymentStatus == 'under_review';

        final canConfirm =
            status == 'pending' && paymentMethod == 'cash';
        final canPrepare = status == 'confirmed';
        final canReady = status == 'preparing';
        final owesDriver =
            _merchantNumber(financials['merchant_owes_driver']) > 0 &&
            order['assigned_driver_id'] != null;
        final driverOwesMerchant =
            _merchantNumber(financials['driver_owes_merchant']) > 0;

        return Scaffold(
          backgroundColor: const Color(0xFFF6F8FC),
          appBar: AppBar(
            title: const Text(
              'Gestionar pedido',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estado: ' + status,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pago: ' +
                            paymentMethod +
                            ' · ' +
                            paymentStatus,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _moneyLine(
                        'Total pagado por cliente',
                        financials['customer_total'],
                        currency,
                        strong: true,
                      ),
                      _moneyLine(
                        'Productos del comercio',
                        financials['merchant_products_amount'],
                        currency,
                      ),
                      _moneyLine(
                        'Pago al repartidor',
                        financials['driver_payout'],
                        currency,
                      ),
                      _moneyLine(
                        'Propina del repartidor',
                        financials['driver_tip'],
                        currency,
                      ),
                      _moneyLine(
                        'Monto de Express',
                        financials['express_margin'],
                        currency,
                      ),
                    ],
                  ),
                ),
              ),
              if (transferReview) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            busy ? null : () => _review(false),
                        icon: const Icon(Icons.close_rounded),
                        label:
                            const Text('Rechazar comprobante'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            busy ? null : () => _review(true),
                        icon: const Icon(Icons.check_rounded),
                        label:
                            const Text('Aprobar transferencia'),
                      ),
                    ),
                  ],
                ),
              ],
              if (canConfirm) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed:
                      busy ? null : () => _setStatus('confirmed'),
                  icon:
                      const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Confirmar pedido'),
                ),
              ],
              if (canPrepare) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed:
                      busy ? null : () => _setStatus('preparing'),
                  icon: const Icon(Icons.soup_kitchen_outlined),
                  label: const Text('Empezar preparación'),
                ),
              ],
              if (canReady) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed:
                      busy ? null : () => _setStatus('ready'),
                  icon: const Icon(Icons.delivery_dining_rounded),
                  label: const Text(
                    'Pedido listo · buscar repartidor',
                  ),
                ),
              ],
              if (owesDriver) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: busy ? null : _markDriverPaid,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text(
                    'Confirmar pago al repartidor',
                  ),
                ),
              ],
              if (driverOwesMerchant) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _settle(
                            'driver_owes_merchant',
                            'Repartidor → comercio',
                          ),
                  icon: const Icon(Icons.storefront_rounded),
                  label: const Text(
                    'Confirmar depósito del repartidor al comercio',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'Chat con el cliente',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
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
              TextField(
                controller: message,
                decoration: InputDecoration(
                  hintText:
                      'Escribe al cliente o envía datos de transferencia…',
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    onPressed: busy ? null : _send,
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

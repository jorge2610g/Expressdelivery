import 'package:flutter/material.dart';

import 'core/runtime_channel.dart';
import 'marketplace_chat_attachments.dart';
import 'marketplace_merchant_settlements.dart';
import 'marketplace_merchant_catalogue.dart';
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
  static const _ink = Color(0xFF202432);
  static const _muted = Color(0xFF687386);
  static const _blue = Color(0xFF315DA8);
  static const _page = Color(0xFFF4F6FA);
  static const _line = Color(0xFFE6EAF0);

  String? merchantId;
  String _filter = 'all';
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

  Future<void> _refresh() async {
    setState(() => future = _load());
    await future;
  }

  Map<String, dynamic>? get currentMerchant {
    for (final row in widget.access) {
      if (row['merchant_id']?.toString() == merchantId) return row;
    }
    return null;
  }

  String _restaurantName() =>
      currentMerchant?['merchant_name']?.toString().trim().isNotEmpty == true
          ? currentMerchant!['merchant_name'].toString()
          : 'Restaurante';

  String _status(Map<String, dynamic> row) =>
      (row['status']?.toString() ?? 'pending').toLowerCase();

  bool _matchesFilter(Map<String, dynamic> row) {
    final status = _status(row);
    switch (_filter) {
      case 'new':
        return const {
          'pending',
          'awaiting_merchant',
          'awaiting_transfer',
          'payment_review',
        }.contains(status);
      case 'preparing':
        return const {'confirmed', 'preparing'}.contains(status);
      case 'ready':
        return status == 'ready';
      case 'delivery':
        return const {
          'searching_driver',
          'driver_assigned',
          'picked_up',
          'delivering',
        }.contains(status);
      case 'done':
        return const {'delivered', 'cancelled'}.contains(status);
      default:
        return true;
    }
  }

  String _statusLabel(String status) => switch (status) {
    'pending' || 'awaiting_merchant' => 'Nuevo',
    'awaiting_transfer' || 'payment_review' => 'Pago por revisar',
    'confirmed' => 'Confirmado',
    'preparing' => 'En preparación',
    'ready' => 'Listo para recoger',
    'searching_driver' => 'Buscando repartidor',
    'driver_assigned' => 'Repartidor asignado',
    'picked_up' => 'Pedido recogido',
    'delivering' => 'En camino',
    'delivered' => 'Entregado',
    'cancelled' => 'Cancelado',
    _ => status.replaceAll('_', ' '),
  };

  Color _statusColor(String status) => switch (status) {
    'pending' || 'awaiting_merchant' => const Color(0xFFB45309),
    'awaiting_transfer' || 'payment_review' => const Color(0xFF7C3AED),
    'preparing' || 'confirmed' => const Color(0xFF2563EB),
    'ready' => const Color(0xFF047857),
    'delivered' => const Color(0xFF15803D),
    'cancelled' => const Color(0xFFB42318),
    _ => const Color(0xFF536273),
  };

  String _paymentLabel(String value) => switch (value.toLowerCase()) {
    'cash' => 'Efectivo',
    'transfer' => 'Transferencia',
    'card' || 'online' => 'Pago en línea',
    '' => 'Pago pendiente',
    _ => value,
  };

  String _orderTime(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Pedido reciente';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month · $hour:$minute';
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

  Future<void> _openCatalogue() async {
    final id = merchantId;
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarketplaceMerchantCataloguePage(
          merchantId: id,
          merchantName: _restaurantName(),
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openSettlements() async {
    final id = merchantId;
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarketplaceMerchantSettlementsPage(
          merchantId: id,
          merchantName: _restaurantName(),
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Widget _summaryCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> row) {
    final status = _status(row);
    final statusColor = _statusColor(status);
    final currency = row['currency_code']?.toString() ?? 'CLP';
    final id = row['id']?.toString() ?? '';
    final shownId = id.length > 8 ? id.substring(0, 8).toUpperCase() : id;
    final payment = _paymentLabel(row['payment_method']?.toString() ?? '');
    final paymentStatus =
        (row['payment_status']?.toString() ?? 'pending').replaceAll('_', ' ');
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: id.isEmpty ? null : () => _openOrder(id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF0FB),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: _blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shownId.isEmpty ? 'Pedido Express' : 'Pedido #$shownId',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _orderTime(row['created_at']),
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Divider(height: 1, color: _line),
              ),
              Text(
                row['customer_name']?.toString() ?? 'Cliente Express',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _detail(Icons.payments_outlined, payment),
                  _detail(Icons.verified_outlined, 'Pago: $paymentStatus'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Total del pedido',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    _merchantMoney(row['total_amount'], currency),
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, color: _muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: _muted),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
    ],
  );

  Widget _emptyState({required bool filtered}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF0FB),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(
            Icons.restaurant_menu_rounded,
            color: _blue,
            size: 34,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          filtered ? 'No hay pedidos en esta sección' : 'Aún no hay pedidos',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Los nuevos pedidos aparecerán aquí para que puedas aceptarlos y prepararlos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Actualizar pedidos'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.access.isEmpty) {
      return const Scaffold(
        backgroundColor: _page,
        body: Center(
          child: Text(
            'No tienes restaurantes vinculados a esta cuenta.',
            style: TextStyle(color: _muted),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Panel del restaurante',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar pedidos',
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
            return const Center(
              child: CircularProgressIndicator(color: _blue),
            );
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _emptyState(filtered: false),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    ExpressRuntimeChannel.userSafeError(
                      snapshot.error,
                      fallback: 'No se pudieron cargar los pedidos.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted),
                  ),
                ),
              ],
            );
          }

          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          final filtered = rows.where(_matchesFilter).toList();
          final newCount = rows.where((row) => const {
            'pending',
            'awaiting_merchant',
            'awaiting_transfer',
            'payment_review',
          }.contains(_status(row))).length;
          final prepCount = rows.where((row) => const {
            'confirmed',
            'preparing',
          }.contains(_status(row))).length;
          final readyCount = rows.where((row) => _status(row) == 'ready').length;
          final deliveryCount = rows.where((row) => const {
            'searching_driver',
            'driver_assigned',
            'picked_up',
            'delivering',
          }.contains(_status(row))).length;

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final contentWidth =
                  constraints.maxWidth > 1200 ? 1120.0 : constraints.maxWidth;
              final horizontal = wide ? 28.0 : 16.0;
              final summaryWidth = wide
                  ? 190.0
                  : ((constraints.maxWidth - horizontal * 2 - 12) / 2)
                      .clamp(145.0, 250.0);
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontal,
                    vertical: wide ? 24 : 18,
                  ),
                  children: [
                    Center(
                      child: SizedBox(
                        width: contentWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(wide ? 24 : 18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: _line),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Pedidos recientes',
                                              style: TextStyle(
                                                color: _ink,
                                                fontSize: 20,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _restaurantName(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: _muted,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEAF7EF),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(
                                              Icons.circle,
                                              size: 8,
                                              color: Color(0xFF16834A),
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'Panel activo',
                                              style: TextStyle(
                                                color: Color(0xFF16834A),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.access.length > 1) ...[
                                    const SizedBox(height: 14),
                                    DropdownButtonFormField<String>(
                                      initialValue: merchantId,
                                      decoration: const InputDecoration(
                                        labelText: 'Restaurante',
                                        prefixIcon: Icon(
                                          Icons.storefront_outlined,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: widget.access
                                          .map(
                                            (row) => DropdownMenuItem<String>(
                                              value: row['merchant_id']
                                                  ?.toString(),
                                              child: Text(
                                                row['merchant_name']
                                                        ?.toString() ??
                                                    'Restaurante',
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setState(() {
                                          merchantId = value;
                                          _filter = 'all';
                                          future = _load();
                                        });
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _openCatalogue,
                                        icon: const Icon(
                                          Icons.restaurant_menu_rounded,
                                        ),
                                        label: const Text('Menú y productos'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: _openSettlements,
                                        icon: const Icon(
                                          Icons.account_balance_wallet_outlined,
                                        ),
                                        label: const Text('Pagos y liquidaciones'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _summaryCard(
                                  title: 'Nuevos',
                                  count: newCount,
                                  icon: Icons.notifications_active_outlined,
                                  color: const Color(0xFFD97706),
                                  width: summaryWidth.toDouble(),
                                ),
                                _summaryCard(
                                  title: 'Preparando',
                                  count: prepCount,
                                  icon: Icons.soup_kitchen_outlined,
                                  color: const Color(0xFF2563EB),
                                  width: summaryWidth.toDouble(),
                                ),
                                _summaryCard(
                                  title: 'Listos',
                                  count: readyCount,
                                  icon: Icons.task_alt_rounded,
                                  color: const Color(0xFF059669),
                                  width: summaryWidth.toDouble(),
                                ),
                                _summaryCard(
                                  title: 'En camino',
                                  count: deliveryCount,
                                  icon: Icons.delivery_dining_rounded,
                                  color: const Color(0xFF7C3AED),
                                  width: summaryWidth.toDouble(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'Pedidos',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _filterChip('all', 'Todos', rows.length),
                                  _filterChip('new', 'Nuevos', newCount),
                                  _filterChip('preparing', 'Preparando', prepCount),
                                  _filterChip('ready', 'Listos', readyCount),
                                  _filterChip('delivery', 'En camino', deliveryCount),
                                  _filterChip(
                                    'done',
                                    'Finalizados',
                                    rows.where((row) => const {
                                      'delivered',
                                      'cancelled',
                                    }.contains(_status(row))).length,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (filtered.isEmpty)
                              _emptyState(filtered: _filter != 'all')
                            else
                              for (final row in filtered) ...[
                                _orderCard(row),
                                const SizedBox(height: 10),
                              ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _filterChip(String key, String label, int count) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text('$label  $count'),
      selected: _filter == key,
      onSelected: (_) => setState(() => _filter = key),
      selectedColor: const Color(0xFFE8EFFC),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: _filter == key ? const Color(0xFFB5C8ED) : _line,
      ),
      labelStyle: TextStyle(
        color: _filter == key ? _blue : _muted,
        fontWeight: _filter == key ? FontWeight.w800 : FontWeight.w600,
      ),
    ),
  );
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
        SnackBar(
          content: Text(
            ExpressRuntimeChannel.userSafeError(
              e,
              fallback: 'No se pudo completar la acción. Intenta nuevamente.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _acceptTransfer() async {
    await _action(() async {
      await widget.service.marketplaceAcceptTransferOrder(widget.orderId);
    });
  }

  Future<void> _sendChatImage() async {
    await _action(() async {
      final path = await marketplacePickAndUploadChatImage(widget.orderId);
      if (path == null) return;
      await widget.service.marketplaceSendOrderMessage(
        orderId: widget.orderId,
        attachmentUrl: path,
        messageType: 'image',
      );
    });
  }

  Future<void> _sendBankDetails() async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    await _action(() async {
      await widget.service.marketplaceSendOrderMessage(
        orderId: widget.orderId,
        body: text,
        messageType: 'bank_details',
      );
      message.clear();
    });
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

        final awaitingMerchant =
            status == 'awaiting_merchant' && paymentMethod == 'transfer';
        final canSendBankDetails =
            paymentMethod == 'transfer' &&
            (status == 'awaiting_transfer' || status == 'payment_review');
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
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                        'Servicio Express · cobrado por adelantado',
                        financials['merchant_owes_express'],
                        currency,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top:8),
                        child: Text(
                          'El Servicio Express se liquida en el corte semanal. '
                          'No incluye el pago en efectivo al repartidor.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (awaitingMerchant) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: busy ? null : _acceptTransfer,
                  icon: const Icon(Icons.store_mall_directory_outlined),
                  label: const Text('Aceptar pedido y habilitar transferencia'),
                ),
                const SizedBox(height: 5),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _setStatus('cancelled'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('No puedo atender · cancelar'),
                ),
              ],
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row['message_type']?.toString() ?? 'mensaje'),
                        if ((row['attachment_url']?.toString() ?? '').isNotEmpty)
                          MarketplaceChatAttachment(
                            objectPath: row['attachment_url'].toString()),
                      ],
                    ),
                  ),
                ),
              ),
              if (canSendBankDetails)
                OutlinedButton.icon(
                  onPressed: busy ? null : _sendBankDetails,
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('Enviar datos bancarios escritos en el chat'),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : _sendChatImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Adjuntar imagen al chat'),
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

import 'dart:async';

import 'package:flutter/material.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'design/express_tokens.dart';
import 'marketplace_merchant_catalogue.dart';
import 'marketplace_merchant_page.dart';
import 'marketplace_merchant_settlements.dart';
import 'money_format.dart';
import 'services/express_service.dart';

/// Secciones del menú lateral del portal de restaurantes.
enum RestaurantSection {
  home('Inicio', Icons.dashboard_outlined),
  orders('Pedidos', Icons.receipt_long_outlined),
  products('Productos', Icons.restaurant_menu_outlined),
  balance('Balance', Icons.account_balance_wallet_outlined),
  profile('Perfil', Icons.storefront_outlined);

  const RestaurantSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _newStatuses = {
  'pending',
  'awaiting_payment',
  'awaiting_merchant',
  'awaiting_transfer',
  'payment_review',
};
const _activeStatuses = {
  ..._newStatuses,
  'confirmed',
  'preparing',
  'ready',
  'searching_driver',
  'driver_assigned',
  'picked_up',
  'delivering',
};

/// Estructura del portal: menú lateral, barra superior con el estado Abierto/Cerrado
/// y las secciones. Reutiliza las pantallas de pedidos, catálogo y liquidaciones.
class RestaurantPortalShell extends StatefulWidget {
  const RestaurantPortalShell({
    super.key,
    required this.service,
    required this.access,
    required this.onLogout,
    this.debugState,
    this.debugOrders,
    this.debugSection,
  });

  /// Solo para capturas de diseño: datos fijos, sin llamadas al servidor.
  final Map<String, dynamic>? debugState;
  final List<Map<String, dynamic>>? debugOrders;
  final RestaurantSection? debugSection;

  final ExpressService service;
  final List<Map<String, dynamic>> access;
  final Future<void> Function() onLogout;

  @override
  State<RestaurantPortalShell> createState() => _RestaurantPortalShellState();
}

class _RestaurantPortalShellState extends State<RestaurantPortalShell> {
  RestaurantSection _section = RestaurantSection.home;
  late String _merchantId;
  Map<String, dynamic> _state = {};
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _merchantId = widget.access.first['merchant_id'].toString();
    if (widget.debugState != null) {
      _state = widget.debugState!;
      _orders = widget.debugOrders ?? const [];
      _loading = false;
      _section = widget.debugSection ?? RestaurantSection.home;
      return;
    }
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, dynamic> get _row => widget.access.firstWhere(
        (r) => r['merchant_id'].toString() == _merchantId,
        orElse: () => widget.access.first,
      );
  String get _name => _row['merchant_name']?.toString().trim().isNotEmpty == true
      ? _row['merchant_name'].toString()
      : 'Restaurante';
  Map<String, dynamic> get _merchant => _state['merchant'] is Map
      ? Map<String, dynamic>.from(_state['merchant'] as Map)
      : <String, dynamic>{};
  Map<String, dynamic> get _stats => _state['stats'] is Map
      ? Map<String, dynamic>.from(_state['stats'] as Map)
      : <String, dynamic>{};
  bool get _open => _merchant['open_override'] != false;
  bool get _canEdit {
    final role = _state['role']?.toString() ?? 'staff';
    return role == 'owner' || role == 'manager';
  }

  String get _currency => _state['currency']?.toString() ?? 'BOB';
  int get _activeCount =>
      _orders.where((o) => _activeStatuses.contains(_status(o))).length;
  int get _newCount =>
      _orders.where((o) => _newStatuses.contains(_status(o))).length;

  String _status(Map<String, dynamic> o) =>
      (o['status']?.toString() ?? 'pending').toLowerCase();

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final id = _merchantId;
      final rawFuture = supabase.rpc('marketplace_merchant_manage_state', params: {
        'p_merchant_id': id,
        'p_channel': ExpressRuntimeChannel.name,
      });
      final ordersFuture = widget.service.marketplaceMerchantOrders(id);
      final raw = await rawFuture;
      final orders = await ordersFuture;
      if (!mounted || id != _merchantId) return;
      setState(() {
        _state = raw is Map ? Map<String, dynamic>.from(raw) : {};
        _orders = orders;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!quiet) {
          _error = ExpressRuntimeChannel.userSafeError(e,
              fallback: 'No se pudo cargar el restaurante.');
        }
        _loading = false;
      });
    }
  }

  Future<void> _setOpen(bool open) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await supabase.rpc('marketplace_merchant_set_open', params: {
        'p_merchant_id': _merchantId,
        'p_open': open,
        'p_channel': ExpressRuntimeChannel.name,
      });
      await _load(quiet: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo cambiar el estado: ${ExpressRuntimeChannel.userSafeError(e, fallback: 'intenta de nuevo')}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _go(RestaurantSection s) {
    setState(() => _section = s);
    if (Scaffold.maybeOf(context)?.isDrawerOpen == true) Navigator.pop(context);
  }

  void _selectMerchant(String id) {
    setState(() {
      _merchantId = id;
      _state = {};
      _orders = const [];
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = _content();
    if (wide) {
      return Scaffold(
        backgroundColor: ExpressColors.ground,
        body: Row(children: [
          SizedBox(width: 248, child: _sidebar()),
          const VerticalDivider(width: 1, color: ExpressColors.border),
          Expanded(
            child: Column(children: [
              _topBar(wide: true),
              Expanded(child: body),
            ]),
          ),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: ExpressColors.ground,
      appBar: AppBar(
        title: Text(_section.label),
        actions: [_openChip(), const SizedBox(width: 8)],
      ),
      drawer: Drawer(child: SafeArea(child: _sidebar())),
      body: body,
    );
  }

  Widget _openChip() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _open ? ExpressColors.mintInk : ExpressColors.coralInk,
            borderRadius: BorderRadius.circular(ExpressRadii.pill),
          ),
          child: Center(
            child: Text(_open ? 'Abierto' : 'Cerrado',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _open ? ExpressColors.mint : ExpressColors.coral)),
          ),
        ),
      );

  Widget _sidebar() => Container(
        color: ExpressColors.surface,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 14),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: ExpressColors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: ExpressColors.text)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(Icons.circle,
                            size: 8,
                            color: _open
                                ? ExpressColors.mint
                                : ExpressColors.coral),
                        const SizedBox(width: 5),
                        Text(_open ? 'Abierto' : 'Cerrado',
                            style: const TextStyle(
                                fontSize: 12,
                                color: ExpressColors.textMuted)),
                      ]),
                    ]),
              ),
            ]),
          ),
          if (widget.access.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: DropdownButtonFormField<String>(
                initialValue: _merchantId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Restaurante'),
                items: [
                  for (final r in widget.access)
                    DropdownMenuItem(
                        value: r['merchant_id'].toString(),
                        child: Text(r['merchant_name']?.toString() ?? 'Restaurante',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v != null) _selectMerchant(v);
                },
              ),
            ),
          const Divider(height: 1, color: ExpressColors.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final s in RestaurantSection.values)
                  _navItem(s,
                      badge: s == RestaurantSection.orders ? _newCount : 0),
              ],
            ),
          ),
          const Divider(height: 1, color: ExpressColors.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextButton.icon(
              onPressed: widget.onLogout,
              style: TextButton.styleFrom(foregroundColor: ExpressColors.coral),
              icon: const Icon(Icons.logout),
              label: const Align(
                  alignment: Alignment.centerLeft, child: Text('Cerrar sesión')),
            ),
          ),
        ]),
      );

  Widget _navItem(RestaurantSection s, {int badge = 0}) {
    final selected = _section == s;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? ExpressColors.blueInk : Colors.transparent,
        borderRadius: BorderRadius.circular(ExpressRadii.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(ExpressRadii.control),
          onTap: () => _go(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              Icon(s.icon,
                  size: 22,
                  color: selected
                      ? ExpressColors.blue
                      : ExpressColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(s.label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected
                            ? ExpressColors.blue
                            : ExpressColors.textSoft)),
              ),
              if (badge > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: ExpressColors.coral,
                      borderRadius: BorderRadius.circular(ExpressRadii.pill)),
                  child: Text('$badge',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _topBar({required bool wide}) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          color: ExpressColors.surface,
          border: Border(bottom: BorderSide(color: ExpressColors.border)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(_section.label,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: ExpressColors.text)),
          ),
          if (_newCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: ActionChip(
                avatar: const Icon(Icons.notifications_active_outlined,
                    size: 18, color: ExpressColors.amber),
                label: Text('$_newCount pedido${_newCount == 1 ? '' : 's'} nuevo${_newCount == 1 ? '' : 's'}'),
                onPressed: () => _go(RestaurantSection.orders),
              ),
            ),
          Text(_open ? 'Abierto' : 'Cerrado',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _open ? ExpressColors.mint : ExpressColors.coral)),
          const SizedBox(width: 6),
          Switch(
              value: _open,
              onChanged: (_canEdit && !_saving) ? _setOpen : null),
          IconButton(
              tooltip: 'Actualizar',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded)),
        ]),
      );

  Widget _content() {
    if (_loading && _state.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _state.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar')),
        ]),
      );
    }
    final key = ValueKey('$_merchantId-${_section.name}');
    return switch (_section) {
      RestaurantSection.home => _home(),
      RestaurantSection.orders => MarketplaceMerchantPanelPage(
          key: key,
          service: widget.service,
          access: [_row],
          embedded: true,
        ),
      RestaurantSection.products => MarketplaceMerchantCataloguePage(
          key: key, merchantId: _merchantId, merchantName: _name),
      RestaurantSection.balance => MarketplaceMerchantSettlementsPage(
          key: key, merchantId: _merchantId, merchantName: _name),
      RestaurantSection.profile => _profile(),
    };
  }

  Widget _card(String title, String value, IconData icon, Color color) {
    final screen = MediaQuery.sizeOf(context).width;
    // En pantallas angostas cada tarjeta ocupa el ancho completo.
    final width = screen < 900 ? screen - 40 : 220.0;
    return SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ExpressColors.surface,
            border: Border.all(color: ExpressColors.border),
            borderRadius: BorderRadius.circular(ExpressRadii.card),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: ExpressColors.text)),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: ExpressColors.textMuted)),
                  ]),
            ),
          ]),
        ),
      );
  }

  Widget _home() {
    final rating = _merchant['rating'];
    final ratingText = rating == null
        ? '—'
        : (double.tryParse(rating.toString()) ?? 0).toStringAsFixed(1);
    final active = _orders.where((o) => _activeStatuses.contains(_status(o))).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: ExpressColors.surface,
                        border: Border.all(color: ExpressColors.border),
                        borderRadius: BorderRadius.circular(ExpressRadii.card),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Recibir pedidos',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text(
                                    _open
                                        ? 'Tu restaurante está abierto y recibe pedidos nuevos.'
                                        : 'Tu restaurante está cerrado: no recibirás pedidos nuevos.',
                                    style: const TextStyle(
                                        color: ExpressColors.textMuted)),
                              ]),
                        ),
                        Switch(
                            value: _open,
                            onChanged:
                                (_canEdit && !_saving) ? _setOpen : null),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      _card('Pedidos activos', '$_activeCount',
                          Icons.local_fire_department_outlined,
                          ExpressColors.amber),
                      _card('Pedidos (30 días)', '${_stats['orders'] ?? 0}',
                          Icons.receipt_long_outlined, ExpressColors.blue),
                      _card(
                          'Ventas de productos',
                          expressMoney(_stats['sales_products'] ?? 0, _currency),
                          Icons.payments_outlined,
                          ExpressColors.mint),
                      _card('Calificación', ratingText, Icons.star_outline_rounded,
                          ExpressColors.amber),
                    ]),
                    const SizedBox(height: 22),
                    const Text('Pedidos activos',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    if (active.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: ExpressColors.surface,
                          border: Border.all(color: ExpressColors.border),
                          borderRadius:
                              BorderRadius.circular(ExpressRadii.card),
                        ),
                        child: const Column(children: [
                          Icon(Icons.restaurant_menu_rounded,
                              size: 34, color: ExpressColors.blue),
                          SizedBox(height: 10),
                          Text('No hay pedidos activos',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          SizedBox(height: 4),
                          Text(
                              'Los pedidos nuevos aparecerán aquí para que puedas aceptarlos y prepararlos.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: ExpressColors.textMuted)),
                        ]),
                      )
                    else
                      for (final o in active) _orderTile(o),
                  ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderTile(Map<String, dynamic> o) {
    final id = o['id']?.toString() ?? '';
    final shown = id.length > 8 ? id.substring(0, 8).toUpperCase() : id;
    final isNew = _newStatuses.contains(_status(o));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ExpressColors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
              color: isNew ? ExpressColors.amber : ExpressColors.border),
          borderRadius: BorderRadius.circular(ExpressRadii.card),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ExpressRadii.card)),
          title: Text('Pedido #$shown',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(isNew ? 'Nuevo · por aceptar' : 'En curso'),
          trailing: Text(
              expressMoney(o['total_amount'] ?? o['subtotal'] ?? 0,
                  o['currency_code'] ?? _currency),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          onTap: id.isEmpty
              ? null
              : () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MarketplaceMerchantOrderPage(
                              service: widget.service, orderId: id)));
                  if (mounted) _load(quiet: true);
                },
        ),
      ),
    );
  }

  Widget _profile() {
    final m = _merchant;
    String v(String k, [String fallback = '—']) {
      final x = m[k]?.toString().trim() ?? '';
      return x.isEmpty ? fallback : x;
    }

    final rows = <(String, String)>[
      ('Nombre', _name),
      ('Descripción', v('description')),
      ('Categoría', v('category_key')),
      ('Dirección', v('address')),
      ('Pedido mínimo', m['minimum_order'] == null ? 'Sin mínimo' : expressMoney(m['minimum_order'], _currency)),
      ('Costo de envío', m['delivery_fee'] == null ? '—' : expressMoney(m['delivery_fee'], _currency)),
      ('Tiempo estimado', m['eta_min_minutes'] == null ? '—' : '${m['eta_min_minutes']}–${m['eta_max_minutes'] ?? m['eta_min_minutes']} min'),
      ('Horario', v('business_hours')),
      ('Calificación', m['rating'] == null ? '—' : v('rating')),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ExpressColors.surface,
                border: Border.all(color: ExpressColors.border),
                borderRadius: BorderRadius.circular(ExpressRadii.card),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Perfil del restaurante',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                  width: 150,
                                  child: Text(r.$1,
                                      style: const TextStyle(
                                          color: ExpressColors.textMuted))),
                              Expanded(
                                  child: Text(r.$2,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600))),
                            ]),
                      ),
                    const Divider(height: 28),
                    const Text(
                        'Para cambiar estos datos escribe a soporte de Express. Pronto podrás editarlos aquí.',
                        style: TextStyle(color: ExpressColors.textMuted)),
                  ]),
            ),
          ),
        ),
      ],
    );
  }
}

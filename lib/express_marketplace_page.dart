import 'package:flutter/material.dart';

import 'marketplace_checkout_page.dart';
import 'marketplace_merchant_page.dart';
import 'services/express_service.dart';

class ExpressMarketplacePage extends StatefulWidget {
  final ExpressService service;
  final double? latitude;
  final double? longitude;

  const ExpressMarketplacePage({
    super.key,
    required this.service,
    this.latitude,
    this.longitude,
  });

  @override
  State<ExpressMarketplacePage> createState() => _ExpressMarketplacePageState();
}

class _ExpressMarketplacePageState extends State<ExpressMarketplacePage> {
  static const _blue = Color(0xFF1769E0);
  static const _ink = Color(0xFF101828);
  static const _muted = Color(0xFF667085);
  static const _surface = Color(0xFFF6F8FC);

  late Future<Map<String, dynamic>> future;
  late Future<List<Map<String, dynamic>>> merchantAccessFuture;
  String? selectedCategory;
  String searchQuery = '';
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    future = widget.service.marketplaceHome(
      latitude: widget.latitude,
      longitude: widget.longitude,
    );
    merchantAccessFuture = widget.service.marketplaceMyMerchantAccess();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      future = widget.service.marketplaceHome(
        latitude: widget.latitude,
        longitude: widget.longitude,
      );
      merchantAccessFuture =
          widget.service.marketplaceMyMerchantAccess();
    });
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  IconData _icon(String? key) {
    switch (key) {
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'shopping_basket':
        return Icons.shopping_basket_rounded;
      case 'local_cafe':
        return Icons.local_cafe_rounded;
      case 'set_meal':
        return Icons.set_meal_rounded;
      case 'shopping_bag':
        return Icons.shopping_bag_rounded;
      case 'pets':
        return Icons.pets_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }

  Color _bannerColor(String? key) {
    switch (key) {
      case 'yellow':
        return const Color(0xFFFFE66D);
      case 'green':
        return const Color(0xFFDFF6E8);
      case 'purple':
        return const Color(0xFFEDE7FF);
      default:
        return const Color(0xFFDCEBFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text(
          'Express Market',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: merchantAccessFuture,
            builder: (context, snapshot) {
              final access =
                  snapshot.data ?? const <Map<String, dynamic>>[];
              if (access.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Panel del comercio',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MarketplaceMerchantPanelPage(
                      service: widget.service,
                      access: access,
                    ),
                  ),
                ),
                icon: const Icon(Icons.store_mall_directory_rounded),
              );
            },
          ),
          IconButton(
            tooltip: 'Express Plus',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExpressPlusPage(service: widget.service),
              ),
            ),
            icon: const Icon(Icons.bolt_rounded),
          ),
          IconButton(
            tooltip: 'Mis pedidos',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MarketplaceOrdersPage(service: widget.service),
              ),
            ),
            icon: const Icon(Icons.receipt_long_rounded),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _MessageState(
              icon: Icons.cloud_off_rounded,
              title: 'No pudimos cargar Express Market',
              subtitle: snapshot.error.toString(),
              action: 'Reintentar',
              onPressed: _refresh,
            );
          }

          final data = snapshot.data ?? const <String, dynamic>{};
          final enabled = data['enabled'] == true;
          final channel = data['channel']?.toString() ?? 'production';
          final settings = data['settings'] is Map
              ? Map<String, dynamic>.from(data['settings'] as Map)
              : <String, dynamic>{};
          final categories = _rows(data['categories']);
          final banners = _rows(data['banners']);
          final merchants = _rows(data['merchants']);
          final normalizedSearch = searchQuery.trim().toLowerCase();
          final visibleMerchants = merchants.where((row) {
            if (selectedCategory != null &&
                row['category_key']?.toString() != selectedCategory) {
              return false;
            }
            if (normalizedSearch.isEmpty) return true;
            final haystack = [
              row['name'],
              row['description'],
              row['category_key'],
              row['category_name'],
              row['search_terms'],
            ].whereType<Object>().map((value) => value.toString()).join(' ');
            return haystack.toLowerCase().contains(normalizedSearch);
          }).toList();

          if (!enabled) {
            return _MessageState(
              icon: Icons.storefront_outlined,
              title: 'Express Market está desactivado',
              subtitle:
                  'Puedes habilitar este módulo para $channel desde el panel administrativo.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        settings['hero_title']?.toString() ??
                            'Todo lo que necesitas, en Express',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                    ),
                    if (channel == 'preview')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'PREVIEW',
                          style: TextStyle(
                            color: Color(0xFFB54708),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  settings['hero_subtitle']?.toString() ??
                      'Comida, mercados, tiendas y más.',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: TextField(
                    controller: searchController,
                    onChanged: (value) => setState(() => searchQuery = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: settings['search_placeholder']?.toString() ??
                          'Locales, productos y promociones',
                      hintStyle: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: _blue),
                      suffixIcon: searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar búsqueda',
                              onPressed: () {
                                searchController.clear();
                                setState(() => searchQuery = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                    ),
                  ),
                ),
                if (banners.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 154,
                    child: PageView.builder(
                      controller: PageController(viewportFraction: .94),
                      itemCount: banners.length,
                      itemBuilder: (context, index) {
                        final banner = banners[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: _bannerColor(
                                banner['style_key']?.toString(),
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        banner['title']?.toString() ??
                                            'Promo Express',
                                        style: const TextStyle(
                                          color: _ink,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        banner['subtitle']?.toString() ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if ((banner['cta_label']
                                                  ?.toString()
                                                  .trim() ??
                                              '')
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                          banner['cta_label'].toString(),
                                          style: const TextStyle(
                                            color: _blue,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .75),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.bolt_rounded,
                                    size: 42,
                                    color: _blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Categorías',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: categories.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 124,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final key = category['category_key']?.toString();
                    final selected =
                        key != null && key == selectedCategory;
                    return Material(
                      color: selected
                          ? const Color(0xFFEAF2FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          setState(() {
                            selectedCategory =
                                selected ? null : key;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFFEAF2FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _icon(category['icon_key']?.toString()),
                                  color: _blue,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                category['name']?.toString() ?? 'Categoría',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Locales',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (selectedCategory != null)
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => selectedCategory = null),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Quitar filtro'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (visibleMerchants.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.store_mall_directory_outlined,
                          color: _blue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            searchQuery.trim().isNotEmpty
                                ? 'No encontramos locales o productos que coincidan con tu búsqueda.'
                                : 'Todavía no hay comercios cargados en esta zona. Puedes agregarlos desde el panel administrativo.',
                            style: const TextStyle(
                              color: _muted,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...visibleMerchants.map(
                    (merchant) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFEAF2FF),
                          child: Icon(
                            Icons.storefront_rounded,
                            color: _blue,
                          ),
                        ),
                        title: Text(
                          merchant['name']?.toString() ?? 'Local',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          [
                            merchant['rating'] == null
                                ? null
                                : '★ ${merchant['rating']}',
                            '${merchant['eta_min_minutes'] ?? 15}-${merchant['eta_max_minutes'] ?? 40} min',
                          ].whereType<String>().join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _MarketplaceMerchantPage(
                                service: widget.service,
                                merchant: merchant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MarketplaceMerchantPage extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic> merchant;

  const _MarketplaceMerchantPage({
    required this.service,
    required this.merchant,
  });

  @override
  State<_MarketplaceMerchantPage> createState() =>
      _MarketplaceMerchantPageState();
}

class _MarketplaceMerchantPageState extends State<_MarketplaceMerchantPage> {
  late Future<Map<String, dynamic>> future;
  final Map<String, int> cart = <String, int>{};

  @override
  void initState() {
    super.initState();
    future = widget.service.marketplaceMerchantDetail(
      widget.merchant['id'].toString(),
    );
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  double _price(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int get cartItems =>
      cart.values.fold<int>(0, (total, qty) => total + qty);

  void _change(String id, int delta) {
    setState(() {
      final next = (cart[id] ?? 0) + delta;
      if (next <= 0) {
        cart.remove(id);
      } else {
        cart[id] = next;
      }
    });
  }

  Future<void> _showCart(
    List<Map<String, dynamic>> products,
    Map<String, dynamic> merchant,
  ) async {
    final indexed = {
      for (final product in products) product['id'].toString(): product,
    };
    final currency = merchant['currency_code']?.toString() ?? 'CLP';
    double total = 0;
    for (final entry in cart.entries) {
      total += _price(indexed[entry.key]?['price']) * entry.value;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tu carrito',
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...cart.entries.map((entry) {
              final product = indexed[entry.key];
              if (product == null) return const SizedBox.shrink();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  product['name']?.toString() ?? 'Producto',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  currency +
                      ' ' +
                      (_price(product['price']) * entry.value)
                          .toStringAsFixed(0),
                ),
                trailing: Text(
                  'x' + entry.value.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              );
            }),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Subtotal',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              trailing: Text(
                currency + ' ' + total.toStringAsFixed(0),
                style: const TextStyle(
                  color: Color(0xFF1769E0),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'El costo al cliente y la ganancia del repartidor se calculan por separado. Puedes pagar con tarjeta/Mercado Pago, transferencia o efectivo según la zona.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF175CD3),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MarketplaceCheckoutPage(
                        service: widget.service,
                        merchant: merchant,
                        products: products,
                        cart: Map<String, int>.from(cart),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.shopping_cart_checkout_rounded),
                label: const Text('Continuar al pago'),
              ),
            ),
          ],
        ),
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
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: _MessageState(
              icon: Icons.cloud_off_rounded,
              title: 'No pudimos abrir este comercio',
              subtitle: snapshot.error.toString(),
            ),
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final merchant = data['merchant'] is Map
            ? Map<String, dynamic>.from(data['merchant'] as Map)
            : widget.merchant;
        final products = _rows(data['products']);
        final currency = merchant['currency_code']?.toString() ?? 'CLP';

        return Scaffold(
          backgroundColor: const Color(0xFFF6F8FC),
          appBar: AppBar(
            title: Text(
              merchant['name']?.toString() ?? 'Comercio',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          bottomNavigationBar: cartItems == 0
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.all(14),
                  child: FilledButton.icon(
                    onPressed: () => _showCart(products, merchant),
                    icon: const Icon(Icons.shopping_bag_rounded),
                    label: Text(
                      'Ver carrito · ' + cartItems.toString(),
                    ),
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant['name']?.toString() ?? 'Comercio',
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      merchant['description']?.toString() ??
                          'Catálogo Express',
                      style: const TextStyle(color: Color(0xFF667085)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '★ ' +
                          (merchant['rating'] ?? '5.0').toString() +
                          ' · ' +
                          (merchant['eta_min_minutes'] ?? 15).toString() +
                          '-' +
                          (merchant['eta_max_minutes'] ?? 40).toString() +
                          ' min',
                      style: const TextStyle(
                        color: Color(0xFF1769E0),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Productos',
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (products.isEmpty)
                const _MessageState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Sin productos todavía',
                  subtitle:
                      'Carga productos desde el panel administrativo para probar este comercio.',
                )
              else
                ...products.map((product) {
                  final id = product['id'].toString();
                  final qty = cart[id] ?? 0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.fastfood_rounded,
                              color: Color(0xFF1769E0),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product['name']?.toString() ?? 'Producto',
                                  style: const TextStyle(
                                    color: Color(0xFF101828),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if ((product['description']
                                            ?.toString()
                                            .trim() ??
                                        '')
                                    .isNotEmpty)
                                  Text(
                                    product['description'].toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF667085),
                                      fontSize: 11,
                                    ),
                                  ),
                                const SizedBox(height: 5),
                                Text(
                                  currency +
                                      ' ' +
                                      _price(product['price'])
                                          .toStringAsFixed(0),
                                  style: const TextStyle(
                                    color: Color(0xFF1769E0),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (qty == 0)
                            IconButton.filled(
                              onPressed: () => _change(id, 1),
                              icon: const Icon(Icons.add_rounded),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => _change(id, -1),
                                  icon: const Icon(Icons.remove_rounded),
                                ),
                                Text(
                                  qty.toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _change(id, 1),
                                  icon: const Icon(Icons.add_rounded),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onPressed;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF1769E0)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF667085),
                height: 1.4,
              ),
            ),
            if (action != null && onPressed != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onPressed,
                child: Text(action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

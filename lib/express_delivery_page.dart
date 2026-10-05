import 'package:flutter/material.dart';

import 'core/runtime_channel.dart';
import 'marketplace_category_page.dart';
import 'marketplace_checkout_page.dart';
import 'marketplace_merchant_page.dart';
import 'services/express_service.dart';

class ExpressDeliveryPage extends StatefulWidget {
  final ExpressService service;
  final double? latitude;
  final double? longitude;

  const ExpressDeliveryPage({
    super.key,
    required this.service,
    this.latitude,
    this.longitude,
  });

  @override
  State<ExpressDeliveryPage> createState() => _ExpressDeliveryPageState();
}

class _ExpressDeliveryPageState extends State<ExpressDeliveryPage> {
  static const blue = Color(0xFF1769E0);
  static const ink = Color(0xFF101828);
  static const muted = Color(0xFF667085);
  static const bg = Color(0xFFF6F8FC);

  late Future<Map<String, dynamic>> future;
  late Future<List<Map<String, dynamic>>> merchantAccessFuture;
  final searchController = TextEditingController();
  String search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _load() {
    future = widget.service.marketplaceHome(
      latitude: widget.latitude,
      longitude: widget.longitude,
    );
    merchantAccessFuture = widget.service.marketplaceMyMerchantAccess();
  }

  void _refresh() => setState(_load);

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  IconData _categoryIcon(String? key) {
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

  void _openMerchant(Map<String, dynamic> merchant) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DeliveryMerchantPage(
          service: widget.service,
          merchant: merchant,
        ),
      ),
    );
  }

  Widget _merchantImage(Map<String, dynamic> merchant) {
    final url = merchant['image_url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      return Container(
        height: 132,
        color: const Color(0xFFEAF2FF),
        alignment: Alignment.center,
        child: const Icon(Icons.storefront_rounded, color: blue, size: 44),
      );
    }
    return SizedBox(
      height: 132,
      width: double.infinity,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFEAF2FF),
          alignment: Alignment.center,
          child: const Icon(Icons.storefront_rounded, color: blue, size: 44),
        ),
      ),
    );
  }

  Widget _merchantCard(Map<String, dynamic> merchant) {
    final currency = merchant['currency_code']?.toString() ?? 'CLP';
    final fee = marketNumber(merchant['delivery_fee']);
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => _openMerchant(merchant),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _merchantImage(merchant),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _Badge(
                    label: '★ ' + (merchant['rating'] ?? '5.0').toString(),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant['name']?.toString() ?? 'Local',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if ((merchant['description']?.toString().trim() ?? '')
                      .isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      merchant['description'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      _Badge(
                        icon: Icons.schedule_rounded,
                        label:
                            '${merchant['eta_min_minutes'] ?? 15}-${merchant['eta_max_minutes'] ?? 40} min',
                      ),
                      _Badge(
                        icon: Icons.delivery_dining_rounded,
                        label: fee <= 0
                            ? 'Envío según zona'
                            : marketMoney(fee, currency),
                      ),
                      if (merchant['plus_enabled'] == true)
                        const _Badge(
                          icon: Icons.bolt_rounded,
                          label: 'Express Plus',
                          highlight: true,
                        ),
                      if (merchant['plus_free_delivery'] == true)
                        const _Badge(
                          icon: Icons.local_shipping_outlined,
                          label: 'Envío gratis',
                          highlight: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text(
          'Express Delivery',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: merchantAccessFuture,
            builder: (context, snapshot) {
              final access = snapshot.data ?? const <Map<String, dynamic>>[];
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
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              title: 'No pudimos cargar Express Delivery',
              subtitle: ExpressRuntimeChannel.userSafeError(
                snapshot.error,
                fallback: 'Intenta nuevamente.',
              ),
              action: _refresh,
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
          final query = search.trim().toLowerCase();
          final visible = merchants.where((merchant) {
            if (query.isEmpty) return true;
            final haystack = [
              merchant['name'],
              merchant['description'],
              merchant['category_key'],
              merchant['category_name'],
              merchant['search_terms'],
            ].whereType<Object>().map((v) => v.toString()).join(' ');
            return haystack.toLowerCase().contains(query);
          }).toList();

          if (!enabled) {
            return _Message(
              title: 'Express Delivery no está disponible',
              subtitle: ExpressRuntimeChannel.technicalOr(
                production: 'Intenta nuevamente más tarde.',
                preview: 'Todavía no está habilitado para $channel.',
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        settings['hero_title']?.toString() ??
                            'Pide lo que quieras con Express Delivery',
                        style: const TextStyle(
                          color: ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                    ),
                    if (ExpressRuntimeChannel.previewMode &&
                        channel == 'preview')
                      const _Badge(label: 'PREVIEW', highlight: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  settings['hero_subtitle']?.toString() ??
                      'Restaurantes, supermercados, farmacia y más.',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: searchController,
                  onChanged: (value) => setState(() => search = value),
                  decoration: InputDecoration(
                    hintText: settings['search_placeholder']?.toString() ??
                        'Busca restaurantes, tiendas o productos',
                    prefixIcon: const Icon(Icons.search_rounded, color: blue),
                    suffixIcon: search.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(() {
                              search = '';
                              searchController.clear();
                            }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (banners.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 150,
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        banner['title']?.toString() ??
                                            'Promo Express',
                                        style: const TextStyle(
                                          color: ink,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        banner['subtitle']?.toString() ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: muted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.delivery_dining_rounded,
                                  color: blue,
                                  size: 48,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                const Text(
                  'Categorías',
                  style: TextStyle(
                    color: ink,
                    fontSize: 19,
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
                    mainAxisExtent: 120,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MarketplaceCategoryPage(
                              categories: categories,
                              merchants: merchants,
                              initialCategory: category,
                              onMerchantTap: _openMerchant,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF2FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _categoryIcon(
                                    category['icon_key']?.toString(),
                                  ),
                                  color: blue,
                                ),
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      category['name']?.toString() ??
                                          'Categoría',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: ink,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: muted,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Restaurantes y locales destacados',
                  style: TextStyle(
                    color: ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Los locales de abajo son recomendaciones generales; las categorías abren su propia pantalla.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const _Message(
                    title: 'No encontramos locales',
                    subtitle: 'Prueba otra búsqueda o entra a una categoría.',
                  )
                else
                  ...visible.map(
                    (merchant) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _merchantCard(merchant),
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

class _DeliveryMerchantPage extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic> merchant;

  const _DeliveryMerchantPage({
    required this.service,
    required this.merchant,
  });

  @override
  State<_DeliveryMerchantPage> createState() =>
      _DeliveryMerchantPageState();
}

class _DeliveryMerchantPageState extends State<_DeliveryMerchantPage> {
  static const blue = Color(0xFF1769E0);
  static const ink = Color(0xFF101828);
  static const muted = Color(0xFF667085);

  late Future<Map<String, dynamic>> future;
  final cart = <String, int>{};
  final searchController = TextEditingController();
  String search = '';

  @override
  void initState() {
    super.initState();
    future = widget.service.marketplaceMerchantDetail(
      widget.merchant['id'].toString(),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  int get count => cart.values.fold<int>(0, (sum, qty) => sum + qty);

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

  Widget _image(String? url, {IconData icon = Icons.restaurant_rounded}) {
    final value = url?.trim() ?? '';
    if (value.isEmpty) {
      return Container(
        color: const Color(0xFFEAF2FF),
        alignment: Alignment.center,
        child: Icon(icon, color: blue, size: 44),
      );
    }
    return Image.network(
      value,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFFEAF2FF),
        alignment: Alignment.center,
        child: Icon(icon, color: blue, size: 44),
      ),
    );
  }

  Future<void> _openCart(
    List<Map<String, dynamic>> products,
    Map<String, dynamic> merchant,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DeliveryCartPage(
          service: widget.service,
          merchant: merchant,
          products: products,
          cart: cart,
        ),
      ),
    );
    if (mounted) setState(() {});
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
            body: _Message(
              title: 'No pudimos abrir este local',
              subtitle: ExpressRuntimeChannel.userSafeError(
                snapshot.error,
                fallback: 'Intenta nuevamente.',
              ),
            ),
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final merchant = data['merchant'] is Map
            ? Map<String, dynamic>.from(data['merchant'] as Map)
            : widget.merchant;
        final products = _rows(data['products']);
        final currency = merchant['currency_code']?.toString() ?? 'CLP';
        final query = search.trim().toLowerCase();
        final visible = products.where((product) {
          if (query.isEmpty) return true;
          final text = [
            product['name'],
            product['description'],
          ].whereType<Object>().map((v) => v.toString()).join(' ');
          return text.toLowerCase().contains(query);
        }).toList();

        return Scaffold(
          backgroundColor: const Color(0xFFF6F8FC),
          appBar: AppBar(
            title: Text(
              merchant['name']?.toString() ?? 'Express Delivery',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          bottomNavigationBar: count == 0
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.all(14),
                  child: FilledButton.icon(
                    onPressed: () => _openCart(products, merchant),
                    icon: const Icon(Icons.shopping_bag_rounded),
                    label: Text('Ver carrito · $count'),
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 110),
            children: [
              SizedBox(
                height: 190,
                width: double.infinity,
                child: _image(merchant['image_url']?.toString()),
              ),
              Transform.translate(
                offset: const Offset(0, -18),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 18,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant['name']?.toString() ?? 'Local',
                        style: const TextStyle(
                          color: ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if ((merchant['description']?.toString().trim() ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          merchant['description'].toString(),
                          style: const TextStyle(color: muted, height: 1.35),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 7,
                        children: [
                          _Badge(
                            icon: Icons.star_rounded,
                            label: '★ ' +
                                (merchant['rating'] ?? '5.0').toString(),
                          ),
                          _Badge(
                            icon: Icons.schedule_rounded,
                            label:
                                '${merchant['eta_min_minutes'] ?? 15}-${merchant['eta_max_minutes'] ?? 40} min',
                          ),
                          if ((merchant['address']?.toString().trim() ?? '')
                              .isNotEmpty)
                            _Badge(
                              icon: Icons.location_on_outlined,
                              label: merchant['address'].toString(),
                            ),
                          if (merchant['plus_enabled'] == true)
                            const _Badge(
                              icon: Icons.bolt_rounded,
                              label: 'Express Plus',
                              highlight: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: searchController,
                  onChanged: (value) => setState(() => search = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar en el menú',
                    prefixIcon: const Icon(Icons.search_rounded, color: blue),
                    suffixIcon: search.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(() {
                              search = '';
                              searchController.clear();
                            }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Text(
                  'Menú',
                  style: TextStyle(
                    color: ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _Message(
                    title: 'No encontramos productos',
                    subtitle: 'Prueba otra búsqueda dentro del menú.',
                  ),
                )
              else
                ...visible.map((product) {
                  final id = product['id'].toString();
                  final qty = cart[id] ?? 0;
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 76,
                            height: 76,
                            child: _image(
                              product['image_url']?.toString(),
                              icon: Icons.fastfood_rounded,
                            ),
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
                                  color: ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if ((product['description']
                                          ?.toString()
                                          .trim() ??
                                      '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  product['description'].toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                marketMoney(product['price'], currency),
                                style: const TextStyle(
                                  color: blue,
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
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _DeliveryCartPage extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic> merchant;
  final List<Map<String, dynamic>> products;
  final Map<String, int> cart;

  const _DeliveryCartPage({
    required this.service,
    required this.merchant,
    required this.products,
    required this.cart,
  });

  @override
  State<_DeliveryCartPage> createState() => _DeliveryCartPageState();
}

class _DeliveryCartPageState extends State<_DeliveryCartPage> {
  static const blue = Color(0xFF1769E0);
  static const ink = Color(0xFF101828);
  static const muted = Color(0xFF667085);

  late final Map<String, Map<String, dynamic>> indexed;

  @override
  void initState() {
    super.initState();
    indexed = {
      for (final product in widget.products)
        product['id'].toString(): product,
    };
  }

  int get count =>
      widget.cart.values.fold<int>(0, (sum, qty) => sum + qty);

  double get subtotal {
    double total = 0;
    for (final entry in widget.cart.entries) {
      total += marketNumber(indexed[entry.key]?['price']) * entry.value;
    }
    return total;
  }

  void _change(String id, int delta) {
    setState(() {
      final next = (widget.cart[id] ?? 0) + delta;
      if (next <= 0) {
        widget.cart.remove(id);
      } else {
        widget.cart[id] = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        widget.merchant['currency_code']?.toString() ?? 'CLP';
    final entries = widget.cart.entries.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text(
          'Tu carrito',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar: count == 0
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(14),
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MarketplaceCheckoutPage(
                      service: widget.service,
                      merchant: widget.merchant,
                      products: widget.products,
                      cart: Map<String, int>.from(widget.cart),
                    ),
                  ),
                ),
                icon: const Icon(Icons.shopping_cart_checkout_rounded),
                label: Text(
                  'Ir al pago · ${marketMoney(subtotal, currency)}',
                ),
              ),
            ),
      body: count == 0
          ? const _Message(
              title: 'Tu carrito está vacío',
              subtitle: 'Agrega productos del menú para continuar.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFEAF2FF),
                        child: Icon(Icons.storefront_rounded, color: blue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.merchant['name']?.toString() ??
                              'Express Delivery',
                          style: const TextStyle(
                            color: ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...entries.map((entry) {
                  final product = indexed[entry.key];
                  if (product == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['name']?.toString() ?? 'Producto',
                                style: const TextStyle(
                                  color: ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                marketMoney(
                                  marketNumber(product['price']) * entry.value,
                                  currency,
                                ),
                                style: const TextStyle(
                                  color: blue,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _change(entry.key, -1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          entry.value.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        IconButton(
                          onPressed: () => _change(entry.key, 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  );
                }),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Subtotal',
                              style: TextStyle(
                                color: ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            marketMoney(subtotal, currency),
                            style: const TextStyle(
                              color: blue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'En el siguiente paso eliges dirección, propina, Express Plus/prioridad y método de pago. Verás el total final antes de confirmar.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool highlight;

  const _Badge({
    this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1769E0);
    const ink = Color(0xFF101828);
    const muted = Color(0xFF667085);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFFEAF2FF)
            : const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: highlight ? blue : muted),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: highlight ? blue : ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? action;

  const _Message({
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.delivery_dining_rounded,
              color: Color(0xFF1769E0),
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF667085),
                height: 1.35,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: action,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

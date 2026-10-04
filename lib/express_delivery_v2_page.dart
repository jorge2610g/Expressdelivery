import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'location_picker.dart';
import 'marketplace_checkout_page.dart';
import 'marketplace_merchant_page.dart';
import 'services/express_service.dart';

const _dBlue = Color(0xFF1769E0);
const _dInkLight = Color(0xFF101828);
const _dMutedLight = Color(0xFF667085);
const _dBgLight = Color(0xFFF6F8FC);
const _dBorderLight = Color(0xFFE4E7EC);

bool _dDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _dCanvas(BuildContext context) =>
    _dDark(context) ? const Color(0xFF0B1018) : _dBgLight;

Color _dSurface(BuildContext context) =>
    _dDark(context) ? const Color(0xFF141B24) : Colors.white;

Color _dSurfaceAlt(BuildContext context) =>
    _dDark(context) ? const Color(0xFF1A2430) : const Color(0xFFF2F4F7);

Color _dText(BuildContext context) =>
    _dDark(context) ? const Color(0xFFF5F7FA) : _dInkLight;

Color _dMutedText(BuildContext context) =>
    _dDark(context) ? const Color(0xFFA7B0BE) : _dMutedLight;

Color _dBorderColor(BuildContext context) =>
    _dDark(context) ? const Color(0xFF2A3646) : _dBorderLight;

Color _dSoftBlue(BuildContext context) =>
    _dDark(context) ? const Color(0xFF132B4F) : const Color(0xFFEAF2FF);

double _dNumber(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _dRows(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

String _dMoney(Object? value, Object? currencyRaw) {
  final amount = _dNumber(value);
  final currency = (currencyRaw?.toString() ?? 'CLP').toUpperCase();
  if (currency == 'CLP') {
    final raw = amount.round().toString();
    final grouped = raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return 'CLP ' + grouped;
  }
  if (currency == 'BOB') {
    final shown = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return 'Bs ' + shown;
  }
  return currency + ' ' + amount.toStringAsFixed(2);
}

String _dDate(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return d + '/' + m + '/' + date.year.toString();
}

double _distanceKm(
  double? lat1,
  double? lng1,
  double? lat2,
  double? lng2,
) {
  if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
    return 0;
  }
  const radius = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

class DeliveryCartItem {
  final Map<String, dynamic> product;
  final List<String> modifierIds;
  final List<Map<String, dynamic>> modifiers;
  final String note;
  int quantity;
  final double unitPrice;

  DeliveryCartItem({
    required this.product,
    required this.modifierIds,
    required this.modifiers,
    required this.note,
    required this.quantity,
    required this.unitPrice,
  });

  String get productId => product['id'].toString();
  String get merchantId => product['merchant_id'].toString();

  String get lineKey {
    final ids = [...modifierIds]..sort();
    return productId + '|' + ids.join(',') + '|' + note.trim();
  }

  double get total => unitPrice * quantity;

  Map<String, dynamic> toRpc() => {
        'product_id': productId,
        'quantity': quantity,
        'modifier_ids': modifierIds,
        'note': note,
      };
}

class ExpressDeliveryV2Page extends StatefulWidget {
  final ExpressService service;
  final double? latitude;
  final double? longitude;
  final VoidCallback? onOpenRide;
  final VoidCallback? onOpenDriver;
  final VoidCallback? onOpenServices;

  const ExpressDeliveryV2Page({
    super.key,
    required this.service,
    this.latitude,
    this.longitude,
    this.onOpenRide,
    this.onOpenDriver,
    this.onOpenServices,
  });

  @override
  State<ExpressDeliveryV2Page> createState() => _ExpressDeliveryV2PageState();
}

class _ExpressDeliveryV2PageState extends State<ExpressDeliveryV2Page> {
  int tab = 0;
  String? zoneId;
  String? addressId;
  int revision = 0;
  final List<DeliveryCartItem> cart = [];

  Future<Map<String, dynamic>> _home() {
    return widget.service.marketplaceHomeV2(
      zoneId: zoneId,
      latitude: widget.latitude,
      longitude: widget.longitude,
      addressId: addressId,
    );
  }

  int get cartCount =>
      cart.fold<int>(0, (sum, item) => sum + item.quantity);

  String? get cartMerchantId =>
      cart.isEmpty ? null : cart.first.merchantId;

  void _reload() => setState(() => revision++);

  void _addCartItem(DeliveryCartItem item) {
    setState(() {
      if (cart.isNotEmpty && cart.first.merchantId != item.merchantId) {
        cart.clear();
      }
      final existing = cart.indexWhere((row) => row.lineKey == item.lineKey);
      if (existing >= 0) {
        cart[existing].quantity += item.quantity;
      } else {
        cart.add(item);
      }
    });
  }

  void _clearCart() => setState(cart.clear);

  Future<void> _pickAddressAndZone(Map<String, dynamic> home) async {
    final addresses = _dRows(home['addresses']);
    final zones = await widget.service.marketplaceAvailableZones();
    if (!mounted) return;

    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AddressZoneSheet(
        service: widget.service,
        zones: zones,
        addresses: addresses,
        currentZoneId: zoneId ?? home['zone']?['id']?.toString(),
        currentAddressId: addressId ?? home['selected_address']?['id']?.toString(),
        initialLatitude: widget.latitude,
        initialLongitude: widget.longitude,
      ),
    );

    if (result == null || !mounted) return;
    final nextZone = result['zone_id'];
    final nextAddress = result['address_id'];
    setState(() {
      if (zoneId != null && nextZone != zoneId && cart.isNotEmpty) {
        cart.clear();
      }
      zoneId = nextZone;
      addressId = nextAddress;
      revision++;
    });
  }

  void _openNotifications(Map<String, dynamic> home) {
    final zone = home['zone'] is Map
        ? Map<String, dynamic>.from(home['zone'] as Map)
        : <String, dynamic>{};
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DeliveryNotificationsPage(
          service: widget.service,
          countryCode: zone['country_code']?.toString(),
        ),
      ),
    ).then((_) => _reload());
  }

  void _openCart(Map<String, dynamic> home) {
    if (cart.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DeliveryCartPage(
          service: widget.service,
          items: cart,
          home: home,
          onChanged: () => setState(() {}),
          onClear: _clearCart,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _openMerchant(
    Map<String, dynamic> merchant,
    Map<String, dynamic> home,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DeliveryMerchantPageV2(
          service: widget.service,
          merchant: merchant,
          cartCount: () => cartCount,
          onAdd: _addCartItem,
          onCart: () => _openCart(home),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('delivery-v2-' + revision.toString()),
      future: _home(),
      builder: (context, snapshot) {
        final home = snapshot.data ?? const <String, dynamic>{};
        final loading =
            snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData;
        final zone = home['zone'] is Map
            ? Map<String, dynamic>.from(home['zone'] as Map)
            : <String, dynamic>{};
        final selectedAddress = home['selected_address'] is Map
            ? Map<String, dynamic>.from(home['selected_address'] as Map)
            : <String, dynamic>{};

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text('Express Delivery')),
            body: _DeliveryError(
              error: snapshot.error.toString(),
              onRetry: _reload,
            ),
          );
        }

        if (!loading && home['enabled'] == false) {
          return Scaffold(
            appBar: AppBar(title: Text('Express Delivery')),
            body: _DeliveryEmpty(
              icon: Icons.location_off_rounded,
              title: 'Express Delivery no está disponible aquí',
              text: home['reason']?.toString() ?? 'Selecciona otra zona.',
              actionLabel: 'Cambiar zona',
              onAction: () => _pickAddressAndZone(home),
            ),
          );
        }

        return Scaffold(
          backgroundColor: _dCanvas(context),
          drawer: _DeliveryQuickDrawer(
            onRide: widget.onOpenRide,
            onRestaurant: () {},
            onDriver: widget.onOpenDriver,
            onServices: widget.onOpenServices,
          ),
          appBar: AppBar(
            backgroundColor: _dSurface(context),
            surfaceTintColor: _dSurface(context),
            foregroundColor: _dText(context),
            titleSpacing: 4,
            leading: Builder(
              builder: (drawerContext) => IconButton(
                tooltip: 'Cambiar servicio',
                onPressed: () => Scaffold.of(drawerContext).openDrawer(),
                icon: Icon(Icons.grid_view_rounded, color: _dText(context)),
              ),
            ),
            title: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: loading ? null : () => _pickAddressAndZone(home),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Express Delivery',
                      style: TextStyle(
                        color: _dText(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: _dBlue,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            selectedAddress['label']?.toString() ??
                                zone['city']?.toString() ??
                                'Seleccionar dirección',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _dMutedText(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: _dMutedText(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              Stack(
                children: [
                  IconButton(
                    tooltip: 'Notificaciones',
                    onPressed: () => _openNotifications(home),
                    icon: Icon(Icons.notifications_none_rounded, color: _dText(context)),
                  ),
                  if (_dNumber(home['unread_notifications']) > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              Stack(
                children: [
                  IconButton(
                    tooltip: 'Carrito',
                    onPressed: cart.isEmpty ? null : () => _openCart(home),
                    icon: Icon(Icons.shopping_bag_outlined, color: _dText(context)),
                  ),
                  if (cartCount > 0)
                    Positioned(
                      right: 5,
                      top: 5,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _dBlue,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          cartCount.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          body: loading
              ? const _DeliveryHomeSkeleton()
              : _bodyForTab(home),
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: _dSurface(context),
              indicatorColor: _dSoftBlue(context),
              height: 64,
              iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
                (states) => IconThemeData(
                  color: states.contains(WidgetState.selected)
                      ? _dBlue
                      : _dMutedText(context),
                  size: 22,
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
                (states) => TextStyle(
                  color: states.contains(WidgetState.selected)
                      ? _dBlue
                      : _dMutedText(context),
                  fontSize: 10.5,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w900
                      : FontWeight.w700,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: tab,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (value) => setState(() => tab = value),
              destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront_rounded),
                label: 'Mercados',
              ),
              NavigationDestination(
                icon: Icon(Icons.local_offer_outlined),
                selectedIcon: Icon(Icons.local_offer_rounded),
                label: 'Promos',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Pedidos',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Perfil',
              ),
            ],
            ),
          ),
        );
      },
    );
  }

  Widget _bodyForTab(Map<String, dynamic> home) {
    switch (tab) {
      case 1:
        return _DeliveryMarketsTab(
          service: widget.service,
          home: home,
          zoneId: zoneId ?? home['zone']?['id']?.toString(),
          onMerchant: (merchant) => _openMerchant(merchant, home),
          onProduct: (product) => _openProduct(product, home),
        );
      case 2:
        return _DeliveryPromotionsTab(
          home: home,
          onMerchant: (merchant) => _openMerchant(merchant, home),
          onProduct: (product) => _openProduct(product, home),
        );
      case 3:
        final zone = home['zone'] is Map
            ? Map<String, dynamic>.from(home['zone'] as Map)
            : <String, dynamic>{};
        return _DeliveryOrdersTab(
          service: widget.service,
          countryCode: zone['country_code']?.toString(),
        );
      case 4:
        return _DeliveryProfileTab(
          service: widget.service,
          home: home,
          onAddress: () => _pickAddressAndZone(home),
        );
      default:
        return _DeliveryHomeTab(
          home: home,
          onRefresh: () async => _reload(),
          onAddress: () => _pickAddressAndZone(home),
          onCategory: (category) => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _DeliveryCategoryPageV2(
                service: widget.service,
                category: category,
                zoneId: zoneId ?? home['zone']?['id']?.toString(),
                onMerchant: (merchant) => _openMerchant(merchant, home),
                onProduct: (product) => _openProduct(product, home),
              ),
            ),
          ),
          onMerchant: (merchant) => _openMerchant(merchant, home),
          onProduct: (product) => _openProduct(product, home),
        );
    }
  }

  void _openProduct(
    Map<String, dynamic> product,
    Map<String, dynamic> home,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DeliveryProductPage(
          service: widget.service,
          productId: product['id'].toString(),
          onAdd: _addCartItem,
          onCart: () => _openCart(home),
          cartCount: () => cartCount,
        ),
      ),
    ).then((_) => setState(() {}));
  }
}

class _DeliveryHomeTab extends StatelessWidget {
  final Map<String, dynamic> home;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddress;
  final ValueChanged<Map<String, dynamic>> onCategory;
  final ValueChanged<Map<String, dynamic>> onMerchant;
  final ValueChanged<Map<String, dynamic>> onProduct;

  const _DeliveryHomeTab({
    required this.home,
    required this.onRefresh,
    required this.onAddress,
    required this.onCategory,
    required this.onMerchant,
    required this.onProduct,
  });

  @override
  Widget build(BuildContext context) {
    final settings = home['settings'] is Map
        ? Map<String, dynamic>.from(home['settings'] as Map)
        : <String, dynamic>{};
    final categories = _dRows(home['categories']);
    final banners = _dRows(home['banners']);
    final merchants = _dRows(home['merchants']);
    final products = _dRows(home['featured_products']);
    final sections = _dRows(home['home_sections']);
    final preferenceTags = home['preference_tags'] is List
        ? (home['preference_tags'] as List)
            .map((e) => e.toString().toLowerCase())
            .toSet()
        : <String>{};
    final zone = home['zone'] is Map
        ? Map<String, dynamic>.from(home['zone'] as Map)
        : <String, dynamic>{};
    final address = home['selected_address'] is Map
        ? Map<String, dynamic>.from(home['selected_address'] as Map)
        : <String, dynamic>{};

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          InkWell(
            onTap: onAddress,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _dSurface(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _dBorderColor(context)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _dSoftBlue(context),
                    child: Icon(Icons.location_on_rounded, color: _dBlue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Entregar en',
                          style: TextStyle(
                            color: _dMutedText(context),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          address['address']?.toString() ??
                              zone['city']?.toString() ??
                              'Selecciona una dirección',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _dText(context),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: _dMutedText(context)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            settings['hero_title']?.toString() ??
                'Pide lo que quieras con Express Delivery',
            style: TextStyle(
              color: _dText(context),
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            settings['hero_subtitle']?.toString() ??
                'Restaurantes, supermercados, farmacia y más.',
            style: TextStyle(color: _dMutedText(context)),
          ),
          const SizedBox(height: 14),
          _DeliverySearchBar(
            hint: settings['search_placeholder']?.toString() ??
                'Busca restaurantes, tiendas o productos',
            merchants: merchants,
            products: products,
            onMerchant: onMerchant,
            onProduct: onProduct,
          ),
          if (banners.isNotEmpty) ...[
            const SizedBox(height: 16),
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
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCEBFF),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  banner['title']?.toString() ?? 'Promo Express',
                                  style: TextStyle(
                                    color: _dText(context),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  banner['subtitle']?.toString() ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: _dMutedText(context)),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.delivery_dining_rounded,
                            color: _dBlue,
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
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Categorías'),
          const SizedBox(height: 10),
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final category = categories[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onCategory(category),
                  child: Container(
                    width: 104,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                    decoration: BoxDecoration(
                      color: _dSurface(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _dBorderColor(context)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _deliveryCategoryIcon(
                            category['icon_key']?.toString(),
                          ),
                          color: _dBlue,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          category['name']?.toString() ?? 'Categoría',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _dText(context),
                            fontSize: 10.5,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (merchants.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionTitle(
              title: 'Restaurantes y locales destacados',
              subtitle: 'Explora opciones cerca de tu dirección.',
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 232,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: merchants.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => SizedBox(
                  width: 255,
                  child: _MerchantCard(
                    merchant: merchants[index],
                    onTap: () => onMerchant(merchants[index]),
                  ),
                ),
              ),
            ),
          ],
          ...sections.map((section) {
            final type = section['section_type']?.toString() ?? 'merchants';
            final rule = section['source_rule']?.toString() ?? 'popular';
            if (type == 'merchants') {
              var rows = [...merchants];
              if (rule == 'trusted') {
                rows.sort((a, b) =>
                    _dNumber(b['rating']).compareTo(_dNumber(a['rating'])));
              } else if (rule == 'manual') {
                final config = section['config'] is Map
                    ? Map<String, dynamic>.from(section['config'] as Map)
                    : <String, dynamic>{};
                final ids = config['merchant_ids'] is List
                    ? (config['merchant_ids'] as List)
                        .map((e) => e.toString())
                        .toList()
                    : <String>[];
                if (ids.isNotEmpty) {
                  rows = rows
                      .where((e) => ids.contains(e['id']?.toString()))
                      .toList()
                    ..sort((a, b) => ids
                        .indexOf(a['id']?.toString() ?? '')
                        .compareTo(ids.indexOf(b['id']?.toString() ?? '')));
                }
              } else if (rule == 'sponsored') {
                rows = rows.where((e) => e['is_sponsored'] == true).toList();
              }
              if (rows.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(
                      title: section['title']?.toString() ?? 'Recomendados',
                      subtitle: section['subtitle']?.toString(),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 232,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: math.min(rows.length, 10),
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, index) => SizedBox(
                          width: 255,
                          child: _MerchantCard(
                            merchant: rows[index],
                            onTap: () => onMerchant(rows[index]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            var rows = [...products];
            if (rule == 'deals') {
              rows = rows
                  .where((e) => _dNumber(e['discount_percent']) > 0)
                  .toList();
            } else if (rule == 'lowest_price') {
              rows.sort((a, b) => _dNumber(a['effective_price'])
                  .compareTo(_dNumber(b['effective_price'])));
            } else if (rule == 'popular') {
              rows.sort((a, b) =>
                  _dNumber(b['sold_count']).compareTo(_dNumber(a['sold_count'])));
            } else if (rule == 'preferences') {
              int score(Map<String, dynamic> row) {
                final tags = row['tags'] is List
                    ? (row['tags'] as List)
                        .map((e) => e.toString().toLowerCase())
                        .toSet()
                    : <String>{};
                final category =
                    row['category_key']?.toString().toLowerCase();
                var value = tags.intersection(preferenceTags).length * 10;
                if (category != null && preferenceTags.contains(category)) {
                  value += 5;
                }
                return value;
              }
              rows.sort((a, b) {
                final byPreference = score(b).compareTo(score(a));
                if (byPreference != 0) return byPreference;
                return _dNumber(b['sold_count'])
                    .compareTo(_dNumber(a['sold_count']));
              });
            } else if (rule == 'manual') {
              final config = section['config'] is Map
                  ? Map<String, dynamic>.from(section['config'] as Map)
                  : <String, dynamic>{};
              final ids = config['product_ids'] is List
                  ? (config['product_ids'] as List)
                      .map((e) => e.toString())
                      .toList()
                  : <String>[];
              if (ids.isNotEmpty) {
                rows = rows.where((e) => ids.contains(e['id']?.toString())).toList()
                  ..sort((a, b) => ids
                      .indexOf(a['id']?.toString() ?? '')
                      .compareTo(ids.indexOf(b['id']?.toString() ?? '')));
              }
            } else if (rule == 'sponsored') {
              rows = rows.where((e) => e['is_sponsored'] == true).toList();
            }
            if (rows.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(
                    title: section['title']?.toString() ?? 'Para ti',
                    subtitle: section['subtitle']?.toString(),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 232,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: math.min(rows.length, 12),
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) => SizedBox(
                        width: 180,
                        child: _ProductCard(
                          product: rows[index],
                          onTap: () => onProduct(rows[index]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DeliveryMarketsTab extends StatelessWidget {
  final ExpressService service;
  final Map<String, dynamic> home;
  final String? zoneId;
  final ValueChanged<Map<String, dynamic>> onMerchant;
  final ValueChanged<Map<String, dynamic>> onProduct;

  const _DeliveryMarketsTab({
    required this.service,
    required this.home,
    required this.zoneId,
    required this.onMerchant,
    required this.onProduct,
  });

  @override
  Widget build(BuildContext context) {
    final categories = _dRows(home['categories']);
    final merchants = _dRows(home['merchants']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const _SectionTitle(
          title: 'Mercados y categorías',
          subtitle: 'Entra a una categoría para ver sus locales y productos.',
        ),
        const SizedBox(height: 12),
        ...categories.map(
          (category) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFEAF2FF),
                child: Icon(
                  _deliveryCategoryIcon(category['icon_key']?.toString()),
                  color: _dBlue,
                ),
              ),
              title: Text(
                category['name']?.toString() ?? 'Categoría',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              trailing: Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _DeliveryCategoryPageV2(
                    service: service,
                    category: category,
                    zoneId: zoneId,
                    onMerchant: onMerchant,
                    onProduct: onProduct,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (merchants.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionTitle(title: 'Todos los locales'),
          const SizedBox(height: 10),
          ...merchants.map(
            (merchant) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MerchantCard(
                merchant: merchant,
                onTap: () => onMerchant(merchant),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DeliveryPromotionsTab extends StatelessWidget {
  final Map<String, dynamic> home;
  final ValueChanged<Map<String, dynamic>> onMerchant;
  final ValueChanged<Map<String, dynamic>> onProduct;

  const _DeliveryPromotionsTab({
    required this.home,
    required this.onMerchant,
    required this.onProduct,
  });

  @override
  Widget build(BuildContext context) {
    final products = _dRows(home['featured_products'])
        .where((p) => _dNumber(p['discount_percent']) > 0)
        .toList();
    final merchants = _dRows(home['merchants'])
        .where((m) =>
            m['has_deals'] == true ||
            m['plus_free_delivery'] == true ||
            m['plus_enabled'] == true)
        .toList();
    final coupons = _dRows(home['available_coupons']);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const _SectionTitle(
          title: 'Promociones',
          subtitle: 'Descuentos, envío gratis y beneficios Express Plus.',
        ),
        const SizedBox(height: 12),
        if (products.isEmpty && merchants.isEmpty && coupons.isEmpty)
          const _DeliveryEmpty(
            icon: Icons.local_offer_outlined,
            title: 'No hay promociones activas',
            text: 'Las promociones de tu zona aparecerán aquí.',
          )
        else ...[
          if (coupons.isNotEmpty) ...[
            Text(
              'Cupones disponibles',
              style: TextStyle(
                color: _dText(context),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ...coupons.map(
              (coupon) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _dSoftBlue(context),
                    child: Icon(Icons.local_offer_rounded, color: _dBlue),
                  ),
                  title: Text(
                    coupon['code']?.toString() ?? 'CUPÓN',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    coupon['title']?.toString() ??
                        coupon['description']?.toString() ??
                        'Promoción Express Delivery',
                  ),
                  trailing: coupon['ends_at'] == null
                      ? null
                      : Text(
                          'Hasta ' + _dDate(coupon['ends_at']),
                          style: TextStyle(
                            color: _dMutedText(context),
                            fontSize: 9,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (products.isNotEmpty) ...[
            Text(
              'Productos con descuento',
              style: TextStyle(
                color: _dText(context),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: products.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 246,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) => _ProductCard(
                product: products[index],
                onTap: () => onProduct(products[index]),
              ),
            ),
          ],
          if (merchants.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'Locales con beneficios',
              style: TextStyle(
                color: _dText(context),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ...merchants.map(
              (merchant) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MerchantCard(
                  merchant: merchant,
                  onTap: () => onMerchant(merchant),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _DeliveryOrdersTab extends StatefulWidget {
  final ExpressService service;
  final String? countryCode;

  const _DeliveryOrdersTab({
    required this.service,
    required this.countryCode,
  });

  @override
  State<_DeliveryOrdersTab> createState() => _DeliveryOrdersTabState();
}

class _DeliveryOrdersTabState extends State<_DeliveryOrdersTab> {
  int revision = 0;

  Future<void> _showDeliveryCode(Map<String, dynamic> order) async {
    try {
      final result = await widget.service.marketplaceIssueOrderCode(
        orderId: order['id'].toString(),
        kind: 'delivery',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Código de entrega'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Muéstrale este código únicamente al repartidor cuando recibas tu pedido.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                result['code']?.toString() ?? '—',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Listo'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack(e);
    }
  }

  Future<void> _review(Map<String, dynamic> order) async {
    int rating = 5;
    String? productId;
    final items = _dRows(order['items'])
        .where((item) => item['product_id'] != null)
        .toList();
    final comment = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Califica tu pedido'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  value: productId,
                  decoration: const InputDecoration(
                    labelText: '¿Qué quieres calificar?',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('El comercio en general'),
                    ),
                    ...items.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item['product_id']?.toString(),
                        child: Text(
                          item['product_name']?.toString() ?? 'Producto',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setLocal(() => productId = value),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (index) => IconButton(
                      onPressed: () => setLocal(() => rating = index + 1),
                      icon: Icon(
                        index < rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: const Color(0xFFFFB020),
                      ),
                    ),
                  ),
                ),
                TextField(
                  controller: comment,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: productId == null
                        ? 'Opinión del comercio'
                        : 'Opinión del producto',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await widget.service.marketplaceSubmitReview(
          orderId: order['id'].toString(),
          rating: rating,
          comment: comment.text.trim(),
          productId: productId,
        );
        _snack(
          productId == null
              ? 'Gracias por calificar el comercio.'
              : 'Gracias por calificar el producto.',
        );
      } catch (e) {
        _snack(e);
      }
    }
    comment.dispose();
  }

  void _snack(Object value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(revision),
      future: widget.service.marketplaceMyOrdersV2(
        countryCode: widget.countryCode,
        limit: 80,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _DeliveryListSkeleton();
        }
        if (snapshot.hasError) {
          return _DeliveryError(
            error: snapshot.error.toString(),
            onRetry: () => setState(() => revision++),
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const _DeliveryEmpty(
            icon: Icons.receipt_long_outlined,
            title: 'Todavía no tienes pedidos',
            text: 'Tus pedidos de Express Delivery aparecerán aquí.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => revision++),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final order = rows[index];
              final status = order['status']?.toString() ?? 'pending';
              final currency = order['currency_code']?.toString() ?? 'CLP';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: _dSoftBlue(context),
                            child: Icon(
                              Icons.delivery_dining_rounded,
                              color: _dBlue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              order['merchant_name']?.toString() ??
                                  'Express Delivery',
                              style: TextStyle(
                                color: _dText(context),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            _dMoney(order['total_amount'], currency),
                            style: TextStyle(
                              color: _dBlue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _orderStatusLabel(status),
                        style: TextStyle(
                          color: _dText(context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _dDate(order['created_at']),
                        style: TextStyle(
                          color: _dMutedText(context),
                          fontSize: 11,
                        ),
                      ),
                      if (status == 'picked_up' ||
                          status == 'delivering' ||
                          status == 'driver_assigned') ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _showDeliveryCode(order),
                          icon: Icon(Icons.pin_rounded),
                          label: Text('Código de entrega'),
                        ),
                      ],
                      if (status == 'delivered') ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _review(order),
                          icon: Icon(Icons.star_outline_rounded),
                          label: Text('Calificar pedido'),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DeliveryProfileTab extends StatelessWidget {
  final ExpressService service;
  final Map<String, dynamic> home;
  final VoidCallback onAddress;

  const _DeliveryProfileTab({
    required this.service,
    required this.home,
    required this.onAddress,
  });

  @override
  Widget build(BuildContext context) {
    final zone = home['zone'] is Map
        ? Map<String, dynamic>.from(home['zone'] as Map)
        : <String, dynamic>{};
    final country = zone['country_code']?.toString() ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle(
          title: 'Mi perfil Delivery',
          subtitle: 'Tus preferencias se mantienen separadas por país.',
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.location_on_outlined),
                title: Text('Direcciones guardadas'),
                subtitle: Text(zone['country']?.toString() ?? ''),
                trailing: Icon(Icons.chevron_right_rounded),
                onTap: onAddress,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.receipt_long_outlined),
                title: Text('Datos de facturación'),
                subtitle: Text(
                  country.isEmpty
                      ? 'Selecciona un país'
                      : 'Perfil de facturación ' + country,
                ),
                trailing: Icon(Icons.chevron_right_rounded),
                onTap: country.isEmpty
                    ? null
                    : () => _editBilling(context, country),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.bolt_rounded),
                title: Text('Express Plus'),
                trailing: Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExpressPlusPage(service: service),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: service.marketplaceMyMerchantAccess(),
          builder: (context, snapshot) {
            final access = snapshot.data ?? const <Map<String, dynamic>>[];
            if (access.isEmpty) return const SizedBox.shrink();
            return Card(
              child: ListTile(
                leading: Icon(Icons.store_mall_directory_outlined),
                title: Text('Panel del comercio'),
                subtitle: Text('Gestiona tus pedidos y operación.'),
                trailing: Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MarketplaceMerchantPanelPage(
                      service: service,
                      access: access,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _editBilling(BuildContext context, String country) async {
    Map<String, dynamic>? current;
    try {
      current = await service.marketplaceBillingProfile(country);
    } catch (_) {}
    if (!context.mounted) return;
    final name = TextEditingController(
      text: current?['legal_name']?.toString() ?? '',
    );
    final tax = TextEditingController(
      text: current?['tax_id']?.toString() ?? '',
    );
    final email = TextEditingController(
      text: current?['email']?.toString() ?? '',
    );
    final address = TextEditingController(
      text: current?['billing_address']?.toString() ?? '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Datos de facturación'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre / razón social',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tax,
                  decoration: const InputDecoration(
                    labelText: 'RUT / NIT / identificación fiscal',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Correo'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(
                    labelText: 'Dirección de facturación',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Guardar'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        await service.marketplaceUpsertBillingProfile(
          countryCode: country,
          legalName: name.text.trim(),
          taxId: tax.text.trim(),
          email: email.text.trim(),
          billingAddress: address.text.trim(),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Datos de facturación guardados.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
    name.dispose();
    tax.dispose();
    email.dispose();
    address.dispose();
  }
}

class _DeliveryCategoryPageV2 extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic> category;
  final String? zoneId;
  final ValueChanged<Map<String, dynamic>> onMerchant;
  final ValueChanged<Map<String, dynamic>> onProduct;

  const _DeliveryCategoryPageV2({
    required this.service,
    required this.category,
    required this.zoneId,
    required this.onMerchant,
    required this.onProduct,
  });

  @override
  State<_DeliveryCategoryPageV2> createState() =>
      _DeliveryCategoryPageV2State();
}

class _DeliveryCategoryPageV2State
    extends State<_DeliveryCategoryPageV2> {
  String sort = 'recommended';
  bool deals = false;
  bool plus = false;
  int? maxEta;
  String? selectedTag;
  int revision = 0;

  Future<Map<String, dynamic>> _load() {
    return widget.service.marketplaceCategoryFeedV2(
      categoryKey: widget.category['category_key'].toString(),
      zoneId: widget.zoneId,
      sort: sort,
      onlyDeals: deals,
      onlyPlus: plus,
      maxEta: maxEta,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dCanvas(context),
      appBar: AppBar(
        title: Text(
          widget.category['name']?.toString() ?? 'Categoría',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(revision),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const _DeliveryListSkeleton();
          }
          if (snapshot.hasError) {
            return _DeliveryError(
              error: snapshot.error.toString(),
              onRetry: () => setState(() => revision++),
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final baseMerchants = _dRows(data['merchants']);
          final baseProducts = _dRows(data['products']);
          final tags = data['tags'] is List
              ? (data['tags'] as List).map((e) => e.toString()).toList()
              : <String>[];
          final products = selectedTag == null
              ? baseProducts
              : baseProducts.where((product) {
                  final productTags = product['tags'] is List
                      ? (product['tags'] as List)
                          .map((e) => e.toString().toLowerCase())
                          .toSet()
                      : <String>{};
                  return productTags.contains(selectedTag!.toLowerCase());
                }).toList();
          final taggedMerchantIds = selectedTag == null
              ? <String>{}
              : products
                  .map((product) => product['merchant_id']?.toString())
                  .whereType<String>()
                  .toSet();
          final merchants = selectedTag == null
              ? baseMerchants
              : baseMerchants
                  .where((merchant) =>
                      taggedMerchantIds.contains(merchant['id']?.toString()))
                  .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChipButton(
                      label: sort == 'recommended'
                          ? 'Ordenar'
                          : sort == 'rating'
                              ? 'Mejor calificados'
                              : sort == 'eta'
                                  ? 'Más rápido'
                                  : 'Menor envío',
                      icon: Icons.swap_vert_rounded,
                      onTap: _pickSort,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('Descuentos'),
                      selected: deals,
                      onSelected: (v) => setState(() {
                        deals = v;
                        revision++;
                      }),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('Express Plus'),
                      selected: plus,
                      onSelected: (v) => setState(() {
                        plus = v;
                        revision++;
                      }),
                    ),
                    const SizedBox(width: 8),
                    _FilterChipButton(
                      label: maxEta == null ? 'Tiempo' : '≤ ' + maxEta.toString() + ' min',
                      icon: Icons.schedule_rounded,
                      onTap: _pickEta,
                    ),
                  ],
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: tags.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (context, index) => ChoiceChip(
                      label: Text(tags[index]),
                      selected: selectedTag == tags[index],
                      onSelected: (value) => setState(
                        () => selectedTag = value ? tags[index] : null,
                      ),
                    ),
                  ),
                ),
              ],
              if (products.isNotEmpty) ...[
                const SizedBox(height: 18),
                const _SectionTitle(
                  title: 'Platos y productos irresistibles',
                  subtitle: 'Explora productos de distintos locales.',
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 232,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: 180,
                      child: _ProductCard(
                        product: products[index],
                        onTap: () => widget.onProduct(products[index]),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _SectionTitle(
                title: 'Locales',
                subtitle: merchants.length.toString() + ' disponibles',
              ),
              const SizedBox(height: 10),
              if (merchants.isEmpty)
                const _DeliveryEmpty(
                  icon: Icons.store_mall_directory_outlined,
                  title: 'Sin locales por ahora',
                  text: 'Prueba otro filtro o categoría.',
                )
              else
                ...merchants.map(
                  (merchant) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MerchantCard(
                      merchant: merchant,
                      onTap: () => widget.onMerchant(merchant),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickSort() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sortTile('recommended', 'Recomendados'),
            _sortTile('rating', 'Mejor calificados'),
            _sortTile('eta', 'Más rápido'),
            _sortTile('delivery_fee', 'Menor costo de envío'),
          ],
        ),
      ),
    );
    if (value != null) {
      setState(() {
        sort = value;
        revision++;
      });
    }
  }

  Widget _sortTile(String value, String label) => ListTile(
        title: Text(label),
        trailing: sort == value ? Icon(Icons.check_rounded) : null,
        onTap: () => Navigator.pop(context, value),
      );

  Future<void> _pickEta() async {
    final value = await showModalBottomSheet<int?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Cualquier tiempo'),
              onTap: () => Navigator.pop(context, -1),
            ),
            for (final minutes in const [20, 30, 45, 60])
              ListTile(
                title: Text('Hasta ' + minutes.toString() + ' min'),
                onTap: () => Navigator.pop(context, minutes),
              ),
          ],
        ),
      ),
    );
    if (value != null) {
      setState(() {
        maxEta = value < 0 ? null : value;
        revision++;
      });
    }
  }
}

class _DeliveryMerchantPageV2 extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic> merchant;
  final ValueChanged<DeliveryCartItem> onAdd;
  final VoidCallback onCart;
  final int Function() cartCount;

  const _DeliveryMerchantPageV2({
    required this.service,
    required this.merchant,
    required this.onAdd,
    required this.onCart,
    required this.cartCount,
  });

  @override
  State<_DeliveryMerchantPageV2> createState() =>
      _DeliveryMerchantPageV2State();
}

class _DeliveryMerchantPageV2State
    extends State<_DeliveryMerchantPageV2> {
  int tab = 0;
  String? sectionId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.service.marketplaceMerchantDetailV2(
        widget.merchant['id'].toString(),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(body: _DeliveryHomeSkeleton());
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: _DeliveryError(error: snapshot.error.toString()),
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final merchant = data['merchant'] is Map
            ? Map<String, dynamic>.from(data['merchant'] as Map)
            : widget.merchant;
        final products = _dRows(data['products']);
        final sections = _dRows(data['menu_sections']);
        final reviews = _dRows(data['reviews']);
        final currency = merchant['currency_code']?.toString() ?? 'CLP';
        final filtered = sectionId == null
            ? products
            : products
                .where((p) => p['menu_section_id']?.toString() == sectionId)
                .toList();

        return Scaffold(
          backgroundColor: _dCanvas(context),
          appBar: AppBar(
            backgroundColor: _dSurface(context),
            surfaceTintColor: _dSurface(context),
            foregroundColor: _dText(context),
            title: Text(
              merchant['name']?.toString() ?? 'Local',
              style: TextStyle(
                color: _dText(context),
                fontWeight: FontWeight.w900,
              ),
            ),
            actions: [
              if (widget.cartCount() > 0)
                IconButton(
                  onPressed: widget.onCart,
                  icon: Badge(
                    label: Text(widget.cartCount().toString()),
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      color: _dText(context),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: widget.cartCount() == 0
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.all(14),
                  child: FilledButton.icon(
                    onPressed: widget.onCart,
                    icon: Icon(Icons.shopping_bag_rounded),
                    label: Text(
                      'Ver carrito · ' + widget.cartCount().toString(),
                    ),
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              _NetworkHero(
                url: merchant['image_url']?.toString(),
                icon: Icons.storefront_rounded,
                height: 158,
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                transform: Matrix4.translationValues(0, -14, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _dSurface(context),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
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
                      style: TextStyle(
                        color: _dText(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      merchant['description']?.toString() ?? '',
                      style: TextStyle(color: _dMutedText(context)),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _MiniPill(
                          icon: Icons.star_rounded,
                          label: '★ ' +
                              (merchant['rating'] ?? '5.0').toString(),
                        ),
                        _MiniPill(
                          icon: Icons.schedule_rounded,
                          label: (merchant['eta_min_minutes'] ?? 15).toString() +
                              '-' +
                              (merchant['eta_max_minutes'] ?? 40).toString() +
                              ' min',
                        ),
                        _MiniPill(
                          icon: Icons.delivery_dining_rounded,
                          label: _dMoney(
                            merchant['delivery_fee'],
                            currency,
                          ),
                        ),
                        if (merchant['plus_enabled'] == true)
                          const _MiniPill(
                            icon: Icons.bolt_rounded,
                            label: 'Express Plus',
                            highlighted: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.restaurant_menu_rounded),
                      label: Text('Menú'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.rate_review_outlined),
                      label: Text('Opiniones'),
                    ),
                    ButtonSegment(
                      value: 2,
                      icon: Icon(Icons.info_outline_rounded),
                      label: Text('Info'),
                    ),
                  ],
                  selected: {tab},
                  onSelectionChanged: (value) =>
                      setState(() => tab = value.first),
                ),
              ),
              const SizedBox(height: 14),
              if (tab == 0) ...[
                if (sections.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      children: [
                        ChoiceChip(
                          label: Text('Todo'),
                          selected: sectionId == null,
                          onSelected: (_) => setState(() => sectionId = null),
                        ),
                        const SizedBox(width: 7),
                        ...sections.expand(
                          (section) => [
                            ChoiceChip(
                              label: Text(section['name']?.toString() ?? 'Menú'),
                              selected:
                                  sectionId == section['id']?.toString(),
                              onSelected: (_) => setState(
                                () => sectionId = section['id']?.toString(),
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                ..._groupProducts(filtered).entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: TextStyle(
                            color: _dText(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...entry.value.map(
                          (product) => Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: _MerchantProductRow(
                              product: product,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _DeliveryProductPage(
                                    service: widget.service,
                                    productId: product['id'].toString(),
                                    onAdd: widget.onAdd,
                                    onCart: widget.onCart,
                                    cartCount: widget.cartCount,
                                  ),
                                ),
                              ).then((_) => setState(() {})),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (tab == 1) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: reviews.isEmpty
                      ? const _DeliveryEmpty(
                          icon: Icons.rate_review_outlined,
                          title: 'Todavía no hay opiniones',
                          text: 'Las opiniones verificadas aparecerán aquí.',
                        )
                      : Column(
                          children: reviews
                              .map((r) => _ReviewCard(review: r))
                              .toList(),
                        ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.location_on_outlined),
                          title: Text('Dirección'),
                          subtitle:
                              Text(merchant['address']?.toString() ?? '—'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.schedule_outlined),
                          title: Text('Horario'),
                          subtitle: Text(
                            merchant['business_hours']?.toString() ??
                                'Según disponibilidad del comercio',
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.shopping_bag_outlined),
                          title: Text('Pedido mínimo'),
                          subtitle: Text(
                            _dMoney(
                              merchant['minimum_order'],
                              currency,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupProducts(
    List<Map<String, dynamic>> rows,
  ) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final section = row['section_name']?.toString() ?? 'Menú';
      result.putIfAbsent(section, () => []).add(row);
    }
    return result;
  }
}

class _DeliveryProductPage extends StatefulWidget {
  final ExpressService service;
  final String productId;
  final ValueChanged<DeliveryCartItem> onAdd;
  final VoidCallback onCart;
  final int Function() cartCount;

  const _DeliveryProductPage({
    required this.service,
    required this.productId,
    required this.onAdd,
    required this.onCart,
    required this.cartCount,
  });

  @override
  State<_DeliveryProductPage> createState() => _DeliveryProductPageState();
}

class _DeliveryProductPageState extends State<_DeliveryProductPage> {
  int quantity = 1;
  final selected = <String>{};
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.service.marketplaceProductDetailV2(widget.productId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(body: _DeliveryHomeSkeleton());
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: _DeliveryError(error: snapshot.error.toString()),
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final product = data['product'] is Map
            ? Map<String, dynamic>.from(data['product'] as Map)
            : <String, dynamic>{};
        final groups = _dRows(data['modifier_groups']);
        final reviews = _dRows(data['reviews']);
        final recommendations = _dRows(data['recommendations']);
        final currency = product['currency_code']?.toString() ?? 'CLP';
        final base = _dNumber(product['effective_price']);
        double extras = 0;
        final selectedOptions = <Map<String, dynamic>>[];
        for (final group in groups) {
          for (final option in _dRows(group['options'])) {
            if (selected.contains(option['id']?.toString())) {
              extras += _dNumber(option['price_delta']);
              selectedOptions.add(option);
            }
          }
        }
        final total = (base + extras) * quantity;

        return Scaffold(
          backgroundColor: _dCanvas(context),
          appBar: AppBar(
            backgroundColor: _dSurface(context),
            surfaceTintColor: _dSurface(context),
            foregroundColor: _dText(context),
            title: Text(
              product['merchant_name']?.toString() ?? 'Producto',
              style: TextStyle(
                color: _dText(context),
                fontWeight: FontWeight.w900,
              ),
            ),
            actions: [
              if (widget.cartCount() > 0)
                IconButton(
                  onPressed: widget.onCart,
                  icon: Badge(
                    label: Text(widget.cartCount().toString()),
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      color: _dText(context),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(14),
            child: FilledButton(
              onPressed: () => _add(product, groups, selectedOptions, base + extras),
              child: Text(
                'Agregar · ' + _dMoney(total, currency),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              _NetworkHero(
                url: product['image_url']?.toString(),
                icon: Icons.fastfood_rounded,
                height: 210,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_dNumber(product['effective_price']) <
                        _dNumber(product['price']))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _dDark(context)
                              ? const Color(0xFF143326)
                              : const Color(0xFFE8F7EE),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          product['promo_label']?.toString() ?? 'Promoción',
                          style: TextStyle(
                            color: Color(0xFF14804A),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      product['name']?.toString() ?? 'Producto',
                      style: TextStyle(
                        color: _dText(context),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      product['description']?.toString() ?? '',
                      style: TextStyle(
                        color: _dMutedText(context),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          _dMoney(product['effective_price'], currency),
                          style: TextStyle(
                            color: _dBlue,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (_dNumber(product['effective_price']) <
                            _dNumber(product['price'])) ...[
                          const SizedBox(width: 8),
                          Text(
                            _dMoney(product['price'], currency),
                            style: TextStyle(
                              color: _dMutedText(context),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFB020),
                          size: 18,
                        ),
                        Text(
                          ' ' + (product['rating'] ?? 0).toString(),
                          style: TextStyle(
                            color: _dText(context),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ...groups.map(
                      (group) => _ModifierGroup(
                        group: group,
                        selected: selected,
                        onToggle: (id) => setState(() {
                          final max =
                              (_dNumber(group['max_select']).round()).clamp(1, 99);
                          final options = _dRows(group['options']);
                          final ids = options
                              .map((e) => e['id']?.toString())
                              .whereType<String>()
                              .toSet();
                          final selectedInGroup =
                              selected.where(ids.contains).toList();
                          if (selected.contains(id)) {
                            selected.remove(id);
                          } else {
                            if (max == 1) {
                              selected.removeAll(ids);
                            } else if (selectedInGroup.length >= max) {
                              return;
                            }
                            selected.add(id);
                          }
                        }),
                        currency: currency,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      maxLines: 1,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Nota del producto',
                        hintText: 'Ej. sin cebolla',
                        prefixIcon: Icon(Icons.notes_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _dSurface(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _dBorderColor(context)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Cantidad',
                            style: TextStyle(
                              color: _dText(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          _CartQtyButton(
                            icon: Icons.remove_rounded,
                            onTap: quantity > 1
                                ? () => setState(() => quantity--)
                                : () {},
                          ),
                          Container(
                            width: 30,
                            alignment: Alignment.center,
                            child: Text(
                              quantity.toString(),
                              style: TextStyle(
                                color: _dText(context),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _CartQtyButton(
                            icon: Icons.add_rounded,
                            onTap: () => setState(() => quantity++),
                          ),
                        ],
                      ),
                    ),
                    if (recommendations.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const _SectionTitle(
                        title: 'Otras personas lo combinaron con',
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 210,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: recommendations.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) => SizedBox(
                            width: 160,
                            child: _ProductCard(
                              product: recommendations[index],
                              onTap: () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _DeliveryProductPage(
                                    service: widget.service,
                                    productId:
                                        recommendations[index]['id'].toString(),
                                    onAdd: widget.onAdd,
                                    onCart: widget.onCart,
                                    cartCount: widget.cartCount,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (reviews.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const _SectionTitle(title: 'Opiniones del producto'),
                      const SizedBox(height: 8),
                      ...reviews.take(5).map((r) => _ReviewCard(review: r)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _add(
    Map<String, dynamic> product,
    List<Map<String, dynamic>> groups,
    List<Map<String, dynamic>> selectedOptions,
    double unitPrice,
  ) {
    for (final group in groups) {
      final options = _dRows(group['options']);
      final ids = options
          .map((e) => e['id']?.toString())
          .whereType<String>()
          .toSet();
      final count = selected.where(ids.contains).length;
      final min = _dNumber(group['min_select']).round();
      final max = _dNumber(group['max_select']).round();
      if (count < min ||
          count > max ||
          (group['required'] == true && count == 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Completa la opción: ' +
                  (group['name']?.toString() ?? 'Selección'),
            ),
          ),
        );
        return;
      }
    }

    widget.onAdd(
      DeliveryCartItem(
        product: product,
        modifierIds: selected.toList(),
        modifiers: selectedOptions,
        note: note.text.trim(),
        quantity: quantity,
        unitPrice: unitPrice,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Producto agregado al carrito.')),
    );
    setState(() {});
  }
}

class _DeliveryCartPage extends StatefulWidget {
  final ExpressService service;
  final List<DeliveryCartItem> items;
  final Map<String, dynamic> home;
  final VoidCallback onChanged;
  final VoidCallback onClear;

  const _DeliveryCartPage({
    required this.service,
    required this.items,
    required this.home,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_DeliveryCartPage> createState() => _DeliveryCartPageState();
}

class _DeliveryCartPageState extends State<_DeliveryCartPage> {
  Future<Map<String, dynamic>>? recommendationsFuture;

  @override
  void initState() {
    super.initState();
    if (widget.items.isNotEmpty) {
      recommendationsFuture = widget.service.marketplaceProductDetailV2(
        widget.items.first.productId,
      );
    }
  }

  double get subtotal =>
      widget.items.fold<double>(0, (sum, item) => sum + item.total);

  @override
  Widget build(BuildContext context) {
    final currency = widget.items.isEmpty
        ? 'CLP'
        : widget.items.first.product['currency_code']?.toString() ?? 'CLP';
    final merchantName = widget.items.isEmpty
        ? 'Express Delivery'
        : widget.items.first.product['merchant_name']?.toString() ??
            'Tu pedido';
    final itemCount =
        widget.items.fold<int>(0, (sum, item) => sum + item.quantity);

    return Scaffold(
      backgroundColor: _dCanvas(context),
      appBar: AppBar(
        backgroundColor: _dSurface(context),
        surfaceTintColor: _dSurface(context),
        foregroundColor: _dText(context),
        title: Text(
          'Carrito',
          style: TextStyle(
            color: _dText(context),
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Badge(
                label: Text(itemCount.toString()),
                isLabelVisible: itemCount > 0,
                child: Icon(
                  Icons.shopping_bag_rounded,
                  color: _dText(context),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.items.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: FilledButton(
                onPressed: _checkout,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(
                  'Continuar · ' + _dMoney(subtotal, currency),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
      body: widget.items.isEmpty
          ? const _DeliveryEmpty(
              icon: Icons.shopping_bag_outlined,
              title: 'Tu carrito está vacío',
              text: 'Agrega productos para continuar.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 92),
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _dSurface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _dBorderColor(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _dSoftBlue(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: _dBlue,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              merchantName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _dText(context),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              itemCount.toString() +
                                  (itemCount == 1
                                      ? ' producto'
                                      : ' productos'),
                              style: TextStyle(
                                color: _dMutedText(context),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _dMoney(subtotal, currency),
                        style: const TextStyle(
                          color: _dBlue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ...List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final unitLabel =
                      _dMoney(item.unitPrice, currency) +
                          ' × ' +
                          item.quantity.toString();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _dSurface(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _dBorderColor(context)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: _NetworkHero(
                              url: item.product['image_url']?.toString(),
                              icon: Icons.fastfood_rounded,
                              height: 64,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product['name']?.toString() ??
                                    'Producto',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _dText(context),
                                  fontWeight: FontWeight.w900,
                                  height: 1.08,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                unitLabel,
                                style: TextStyle(
                                  color: _dMutedText(context),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (item.modifiers.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 3,
                                  children: item.modifiers
                                      .map(
                                        (e) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _dSurfaceAlt(context),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            e['name']?.toString() ?? '',
                                            style: TextStyle(
                                              color: _dMutedText(context),
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                              if (item.note.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.notes_rounded,
                                      size: 13,
                                      color: _dBlue,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        item.note,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _dMutedText(context),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 5),
                              Text(
                                _dMoney(item.total, currency),
                                style: const TextStyle(
                                  color: _dBlue,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: _dSurfaceAlt(context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _CartQtyButton(
                                icon: Icons.add_rounded,
                                onTap: () => setState(() {
                                  item.quantity++;
                                  widget.onChanged();
                                }),
                              ),
                              Text(
                                item.quantity.toString(),
                                style: TextStyle(
                                  color: _dText(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              _CartQtyButton(
                                icon: Icons.remove_rounded,
                                onTap: () => setState(() {
                                  item.quantity--;
                                  if (item.quantity <= 0) {
                                    widget.items.removeAt(index);
                                  }
                                  widget.onChanged();
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                FutureBuilder<Map<String, dynamic>>(
                  future: recommendationsFuture,
                  builder: (context, snapshot) {
                    final recommendations =
                        _dRows(snapshot.data?['recommendations']);
                    if (recommendations.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        const _SectionTitle(
                          title: 'Agrega algo más',
                          subtitle: 'Recíbelo todo junto.',
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 204,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: recommendations.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 9),
                            itemBuilder: (context, index) => SizedBox(
                              width: 154,
                              child: _ProductCard(
                                product: recommendations[index],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _DeliveryProductPage(
                                      service: widget.service,
                                      productId:
                                          recommendations[index]['id'].toString(),
                                      onAdd: (item) {
                                        setState(() {
                                          final existing =
                                              widget.items.indexWhere(
                                            (row) =>
                                                row.lineKey == item.lineKey,
                                          );
                                          if (existing >= 0) {
                                            widget.items[existing].quantity +=
                                                item.quantity;
                                          } else {
                                            widget.items.add(item);
                                          }
                                          widget.onChanged();
                                        });
                                      },
                                      onCart: () => Navigator.pop(context),
                                      cartCount: () =>
                                          widget.items.fold<int>(
                                        0,
                                        (sum, row) => sum + row.quantity,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: _dSurface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _dBorderColor(context)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Subtotal',
                        style: TextStyle(
                          color: _dText(context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _dMoney(subtotal, currency),
                        style: const TextStyle(
                          color: _dBlue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _checkout() {
    if (widget.items.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DeliveryCheckoutV2Page(
          service: widget.service,
          items: widget.items,
          home: widget.home,
          onOrderPlaced: () {
            widget.onClear();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }
}

class _DeliveryCheckoutV2Page extends StatefulWidget {
  final ExpressService service;
  final List<DeliveryCartItem> items;
  final Map<String, dynamic> home;
  final VoidCallback onOrderPlaced;

  const _DeliveryCheckoutV2Page({
    required this.service,
    required this.items,
    required this.home,
    required this.onOrderPlaced,
  });

  @override
  State<_DeliveryCheckoutV2Page> createState() =>
      _DeliveryCheckoutV2PageState();
}

class _DeliveryCheckoutV2PageState
    extends State<_DeliveryCheckoutV2Page> {
  String paymentMethod = 'cash';
  String deliveryOption = 'door';
  double tip = 0;
  double donation = 0;
  bool priority = false;
  bool placing = false;
  final coupon = TextEditingController();
  final merchantNote = TextEditingController();
  final deliveryInstructions = TextEditingController();
  Map<String, dynamic>? quote;
  Map<String, dynamic> merchantDetail = <String, dynamic>{};
  String? billingProfileId;

  @override
  void initState() {
    super.initState();
    _loadBillingAndQuote();
  }

  @override
  void dispose() {
    coupon.dispose();
    merchantNote.dispose();
    deliveryInstructions.dispose();
    super.dispose();
  }

  Map<String, dynamic> get address {
    return widget.home['selected_address'] is Map
        ? Map<String, dynamic>.from(widget.home['selected_address'] as Map)
        : <String, dynamic>{};
  }

  Map<String, dynamic> get zone {
    return widget.home['zone'] is Map
        ? Map<String, dynamic>.from(widget.home['zone'] as Map)
        : <String, dynamic>{};
  }

  Map<String, dynamic> get merchant =>
      merchantDetail.isNotEmpty ? merchantDetail : widget.items.first.product;

  Future<void> _loadBillingAndQuote() async {
    try {
      final detail = await widget.service.marketplaceMerchantDetailV2(
        widget.items.first.merchantId,
      );
      if (detail['merchant'] is Map) {
        merchantDetail =
            Map<String, dynamic>.from(detail['merchant'] as Map);
      }
    } catch (_) {}
    final country = zone['country_code']?.toString();
    if (country != null && country.isNotEmpty) {
      try {
        final profile = await widget.service.marketplaceBillingProfile(country);
        billingProfileId = profile?['id']?.toString();
      } catch (_) {}
    }
    await _requote();
  }

  Future<void> _requote() async {
    try {
      final distance = _distanceKm(
        _dNumber(merchant['latitude']) == 0
            ? null
            : _dNumber(merchant['latitude']),
        _dNumber(merchant['longitude']) == 0
            ? null
            : _dNumber(merchant['longitude']),
        _dNumber(address['latitude']) == 0
            ? null
            : _dNumber(address['latitude']),
        _dNumber(address['longitude']) == 0
            ? null
            : _dNumber(address['longitude']),
      );
      final value = await widget.service.marketplaceQuoteV2(
        merchantId: widget.items.first.merchantId,
        items: widget.items.map((e) => e.toRpc()).toList(),
        distanceKm: distance,
        tip: tip,
        priority: priority,
        couponCode: coupon.text.trim().isEmpty ? null : coupon.text.trim(),
        donation: donation,
      );
      if (mounted) setState(() => quote = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        quote?['currency_code']?.toString() ??
            zone['currency_code']?.toString() ??
            'CLP';

    final storeLat = _dNumber(merchant['latitude']);
    final storeLng = _dNumber(merchant['longitude']);
    final userLat = _dNumber(address['latitude']);
    final userLng = _dNumber(address['longitude']);

    return Scaffold(
      backgroundColor: _dCanvas(context),
      appBar: AppBar(
        backgroundColor: _dSurface(context),
        surfaceTintColor: _dSurface(context),
        foregroundColor: _dText(context),
        title: Text(
          'Último paso',
          style: TextStyle(
            color: _dText(context),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: FilledButton(
          onPressed: placing ? null : _placeOrder,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          child: placing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Confirmar · ' +
                      _dMoney(quote?['total_amount'], currency),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 92),
        children: [
          _CheckoutBlock(
            title: 'Entrega',
            icon: Icons.location_on_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CheckoutMiniMap(
                  storeLatitude: storeLat == 0 ? null : storeLat,
                  storeLongitude: storeLng == 0 ? null : storeLng,
                  userLatitude: userLat == 0 ? null : userLat,
                  userLongitude: userLng == 0 ? null : userLng,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.home_work_outlined,
                      size: 17,
                      color: _dBlue,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            address['label']?.toString() ??
                                'Dirección seleccionada',
                            style: TextStyle(
                              color: _dText(context),
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            address['address']?.toString() ??
                                'Mi ubicación actual',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _dMutedText(context),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _CheckoutBlock(
            title: 'Cómo entregar',
            icon: Icons.door_front_door_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _deliveryOptionChip('door', 'En puerta'),
                      const SizedBox(width: 6),
                      _deliveryOptionChip('call', 'Llamarme'),
                      const SizedBox(width: 6),
                      _deliveryOptionChip('concierge', 'Conserjería'),
                      const SizedBox(width: 6),
                      _deliveryOptionChip('leave_at_door', 'Dejar afuera'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: deliveryInstructions,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Indicaciones al repartidor',
                    prefixIcon: Icon(Icons.notes_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _CheckoutBlock(
            title: 'Nota para el local',
            icon: Icons.storefront_outlined,
            child: TextField(
              controller: merchantNote,
              maxLines: 1,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Ej. no enviar cubiertos',
                prefixIcon: Icon(Icons.edit_note_rounded, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _CheckoutBlock(
            title: 'Propina',
            icon: Icons.volunteer_activism_outlined,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _tipOptions(currency).length; i++) ...[
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      labelPadding:
                          const EdgeInsets.symmetric(horizontal: 2),
                      label: Text(
                        _tipOptions(currency)[i] == 0
                            ? 'Sin propina'
                            : _dMoney(
                                _tipOptions(currency)[i],
                                currency,
                              ),
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: tip == _tipOptions(currency)[i],
                      onSelected: (_) {
                        setState(() => tip = _tipOptions(currency)[i]);
                        _requote();
                      },
                    ),
                    if (i < _tipOptions(currency).length - 1)
                      const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _CheckoutBlock(
            title: 'Express Plus',
            icon: Icons.bolt_rounded,
            child: SwitchListTile.adaptive(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              value: priority,
              onChanged: quote?['priority_enabled'] == false
                  ? null
                  : (value) {
                      setState(() => priority = value);
                      _requote();
                    },
              title: Text(
                'Entrega prioritaria',
                style: TextStyle(
                  color: _dText(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                quote?['plus_priority_included_applied'] == true
                    ? 'Incluida con tu beneficio.'
                    : 'Prioriza la asignación.',
                style: TextStyle(
                  color: _dMutedText(context),
                  fontSize: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _CheckoutBlock(
            title: 'Cupón',
            icon: Icons.local_offer_outlined,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: coupon,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Código promocional',
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                FilledButton.tonal(
                  onPressed: _requote,
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _CheckoutBlock(
            title: 'Método de pago',
            icon: Icons.payments_outlined,
            child: SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (quote?['cash_enabled'] != false) ...[
                    _PaymentChoiceCard(
                      value: 'cash',
                      label: 'Efectivo',
                      subtitle: 'Paga al recibir',
                      icon: Icons.payments_rounded,
                      selected: paymentMethod == 'cash',
                      onTap: () =>
                          setState(() => paymentMethod = 'cash'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (quote?['transfer_enabled'] != false) ...[
                    _PaymentChoiceCard(
                      value: 'transfer',
                      label: 'Transferencia',
                      subtitle: 'Banco / QR',
                      icon: Icons.qr_code_2_rounded,
                      selected: paymentMethod == 'transfer',
                      onTap: () =>
                          setState(() => paymentMethod = 'transfer'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (quote?['online_enabled'] == true)
                    _PaymentChoiceCard(
                      value: 'mercado_pago',
                      label: 'Tarjeta',
                      subtitle: 'Pago online',
                      icon: Icons.credit_card_rounded,
                      selected: paymentMethod == 'mercado_pago',
                      onTap: () =>
                          setState(() => paymentMethod = 'mercado_pago'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _CheckoutCompactAction(
                  icon: Icons.receipt_long_outlined,
                  label: billingProfileId == null
                      ? 'Facturación'
                      : 'Facturación ✓',
                  onTap: _editBilling,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CheckoutCompactAction(
                  icon: Icons.favorite_outline_rounded,
                  label: donation > 0
                      ? 'Donación ' + _dMoney(donation, currency)
                      : 'Donación',
                  onTap: () => _pickDonation(currency),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CheckoutBlock(
            title: 'Resumen',
            icon: Icons.receipt_outlined,
            child: Column(
              children: [
                _summaryRow('Productos', quote?['subtotal'], currency),
                if (_dNumber(quote?['product_discount']) > 0)
                  _summaryRow(
                    'Descuentos',
                    -_dNumber(quote?['product_discount']),
                    currency,
                  ),
                _summaryRow(
                  'Envío',
                  quote?['customer_delivery_fee'],
                  currency,
                ),
                if (_dNumber(quote?['priority_fee']) > 0)
                  _summaryRow(
                    'Prioridad',
                    quote?['priority_fee'],
                    currency,
                  ),
                if (_dNumber(quote?['tip_amount']) > 0)
                  _summaryRow(
                    'Propina',
                    quote?['tip_amount'],
                    currency,
                  ),
                if (_dNumber(quote?['donation_amount']) > 0)
                  _summaryRow(
                    'Donación',
                    quote?['donation_amount'],
                    currency,
                  ),
                const Divider(height: 12),
                _summaryRow(
                  'Total',
                  quote?['total_amount'],
                  currency,
                  bold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDonation(String currency) async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in _donationOptions(currency))
                ChoiceChip(
                  label: Text(
                    value == 0 ? 'No ahora' : _dMoney(value, currency),
                  ),
                  selected: donation == value,
                  onSelected: (_) => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      setState(() => donation = selected);
      _requote();
    }
  }

  List<double> _tipOptions(String currency) =>
      currency == 'CLP' ? const [0, 500, 1000, 2000] : const [0, 2, 5, 10];

  List<double> _donationOptions(String currency) =>
      currency == 'CLP' ? const [0, 500, 1000] : const [0, 1, 2];

  Widget _deliveryOptionChip(String value, String label) => ChoiceChip(
        visualDensity: VisualDensity.compact,
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        label: Text(label, style: const TextStyle(fontSize: 10.5)),
        selected: deliveryOption == value,
        onSelected: (_) => setState(() => deliveryOption = value),
      );

  Widget _summaryRow(
    String label,
    Object? amount,
    String currency, {
    bool bold = false,
  }) {
    final value = _dNumber(amount);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _dText(context),
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            (value < 0 ? '- ' : '') + _dMoney(value.abs(), currency),
            style: TextStyle(
              color: bold ? _dBlue : _dText(context),
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editBilling() async {
    final country = zone['country_code']?.toString();
    if (country == null || country.isEmpty) return;
    Map<String, dynamic>? current;
    try {
      current = await widget.service.marketplaceBillingProfile(country);
    } catch (_) {}
    if (!mounted) return;
    final name = TextEditingController(
      text: current?['legal_name']?.toString() ?? '',
    );
    final tax = TextEditingController(
      text: current?['tax_id']?.toString() ?? '',
    );
    final email = TextEditingController(
      text: current?['email']?.toString() ?? '',
    );
    final billing = TextEditingController(
      text: current?['billing_address']?.toString() ?? '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Datos de facturación'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre / razón social',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tax,
                  decoration: const InputDecoration(
                    labelText: 'RUT / NIT',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Correo'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: billing,
                  decoration: const InputDecoration(
                    labelText: 'Dirección de facturación',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Guardar'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        final result = await widget.service.marketplaceUpsertBillingProfile(
          countryCode: country,
          legalName: name.text.trim(),
          taxId: tax.text.trim(),
          email: email.text.trim(),
          billingAddress: billing.text.trim(),
        );
        if (mounted) {
          setState(() => billingProfileId = result['id']?.toString());
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
    name.dispose();
    tax.dispose();
    email.dispose();
    billing.dispose();
  }

  Future<void> _placeOrder() async {
    if (address['address'] == null && widget.home['selected_address'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una dirección de entrega.')),
      );
      return;
    }
    setState(() => placing = true);
    try {
      final distance = _distanceKm(
        _dNumber(merchant['latitude']) == 0
            ? null
            : _dNumber(merchant['latitude']),
        _dNumber(merchant['longitude']) == 0
            ? null
            : _dNumber(merchant['longitude']),
        _dNumber(address['latitude']) == 0
            ? null
            : _dNumber(address['latitude']),
        _dNumber(address['longitude']) == 0
            ? null
            : _dNumber(address['longitude']),
      );
      final result = await widget.service.marketplaceCreateOrderV2(
        merchantId: widget.items.first.merchantId,
        items: widget.items.map((e) => e.toRpc()).toList(),
        paymentMethod: paymentMethod,
        dropoffAddress:
            address['address']?.toString() ?? 'Mi ubicación actual',
        dropoffLatitude: _dNumber(address['latitude']) == 0
            ? null
            : _dNumber(address['latitude']),
        dropoffLongitude: _dNumber(address['longitude']) == 0
            ? null
            : _dNumber(address['longitude']),
        savedAddressId: address['id']?.toString(),
        distanceKm: distance,
        tip: tip,
        priority: priority,
        couponCode: coupon.text.trim().isEmpty ? null : coupon.text.trim(),
        merchantNote: merchantNote.text.trim(),
        deliveryInstructions: deliveryInstructions.text.trim(),
        deliveryOption: deliveryOption,
        donation: donation,
        billingProfileId: billingProfileId,
      );
      final order = result['order'] is Map
          ? Map<String, dynamic>.from(result['order'] as Map)
          : <String, dynamic>{};

      if (paymentMethod == 'mercado_pago' && order['id'] != null) {
        final payment = await widget.service.marketplaceCreateOnlinePayment(
          order['id'].toString(),
        );
        final url = payment['checkout_url']?.toString() ??
            payment['online_checkout_url']?.toString();
        if (url != null && url.isNotEmpty) {
          await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          );
        }
      }

      widget.onOrderPlaced();
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => _DeliveryOrderPlacedPage(
            order: order,
            currency: quote?['currency_code']?.toString() ??
                zone['currency_code']?.toString() ??
                'CLP',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => placing = false);
    }
  }
}

class _DeliveryOrderPlacedPage extends StatelessWidget {
  final Map<String, dynamic> order;
  final String currency;

  const _DeliveryOrderPlacedPage({
    required this.order,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dCanvas(context),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Pedido creado',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(22),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _dSurface(context),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Color(0xFFEAF7EE),
                child: Icon(
                  Icons.check_rounded,
                  color: Color(0xFF14804A),
                  size: 36,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '¡Recibimos tu pedido!',
                style: TextStyle(
                  color: _dText(context),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Te avisaremos en cada etapa: confirmado, preparando, repartidor asignado y entrega.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _dMutedText(context)),
              ),
              const SizedBox(height: 14),
              Text(
                _dMoney(order['total_amount'], currency),
                style: TextStyle(
                  color: _dBlue,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Volver a Express Delivery'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryNotificationsPage extends StatefulWidget {
  final ExpressService service;
  final String? countryCode;

  const _DeliveryNotificationsPage({
    required this.service,
    required this.countryCode,
  });

  @override
  State<_DeliveryNotificationsPage> createState() =>
      _DeliveryNotificationsPageState();
}

class _DeliveryNotificationsPageState
    extends State<_DeliveryNotificationsPage> {
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dCanvas(context),
      appBar: AppBar(
        title: Text(
          'Notificaciones',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(revision),
        future: widget.service.marketplaceDeliveryNotifications(
          countryCode: widget.countryCode,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const _DeliveryListSkeleton();
          }
          if (snapshot.hasError) {
            return _DeliveryError(error: snapshot.error.toString());
          }
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return const _DeliveryEmpty(
              icon: Icons.notifications_none_rounded,
              title: 'Sin notificaciones',
              text: 'Tus pedidos, promociones y avisos aparecerán aquí.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              final unread = row['is_read'] != true;
              return Material(
                color: unread ? const Color(0xFFEAF2FF) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: ListTile(
                  leading: Icon(
                    _notificationIcon(row['type']?.toString()),
                    color: _dBlue,
                  ),
                  title: Text(
                    row['title']?.toString() ?? 'Express Delivery',
                    style: TextStyle(
                      fontWeight:
                          unread ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    row['body']?.toString() ?? '',
                  ),
                  trailing: Text(
                    _dDate(row['created_at']),
                    style: TextStyle(
                      color: _dMutedText(context),
                      fontSize: 9,
                    ),
                  ),
                  onTap: () async {
                    if (unread) {
                      await widget.service.marketplaceMarkNotificationRead(
                        row['id'].toString(),
                      );
                      if (mounted) setState(() => revision++);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddressZoneSheet extends StatefulWidget {
  final ExpressService service;
  final List<Map<String, dynamic>> zones;
  final List<Map<String, dynamic>> addresses;
  final String? currentZoneId;
  final String? currentAddressId;
  final double? initialLatitude;
  final double? initialLongitude;

  const _AddressZoneSheet({
    required this.service,
    required this.zones,
    required this.addresses,
    required this.currentZoneId,
    required this.currentAddressId,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<_AddressZoneSheet> createState() => _AddressZoneSheetState();
}

class _AddressZoneSheetState extends State<_AddressZoneSheet> {
  late String? selectedZoneId;
  String? selectedAddressId;
  late List<Map<String, dynamic>> addresses;

  @override
  void initState() {
    super.initState();
    selectedZoneId = widget.currentZoneId;
    selectedAddressId = widget.currentAddressId;
    addresses = [...widget.addresses];
  }

  @override
  Widget build(BuildContext context) {
    final currentZone = widget.zones.firstWhere(
      (z) => z['id']?.toString() == selectedZoneId,
      orElse: () => <String, dynamic>{},
    );
    final countryCode = currentZone['country_code']?.toString();
    final visibleAddresses = addresses.where((a) {
      final code = a['country_code']?.toString();
      return code == null || code.isEmpty || code == countryCode;
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Dónde quieres recibir?',
                style: TextStyle(
                  color: _dText(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _dSoftBlue(context),
                  child: Icon(Icons.public_rounded, color: _dBlue),
                ),
                title: Text(
                  currentZone['country']?.toString() ?? 'Seleccionar país',
                ),
                subtitle: Text(
                  currentZone['city']?.toString() ?? 'Seleccionar zona',
                ),
                trailing: Text(
                  'Cambiar país',
                  style: TextStyle(
                    color: _dBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: _pickZone,
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    ...visibleAddresses.map(
                      (row) => RadioListTile<String>(
                        value: row['id'].toString(),
                        groupValue: selectedAddressId,
                        onChanged: (value) => setState(
                          () => selectedAddressId = value,
                        ),
                        title: Text(
                          row['label']?.toString() ?? 'Dirección',
                        ),
                        subtitle: Text(
                          row['address']?.toString() ?? '',
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.add_location_alt_outlined,
                        color: _dBlue,
                      ),
                      title: Text(
                        'Nueva dirección',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      onTap: _addAddress,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selectedZoneId == null
                      ? null
                      : () => Navigator.pop(
                            context,
                            {
                              'zone_id': selectedZoneId,
                              'address_id': selectedAddressId,
                            },
                          ),
                  child: Text('Usar esta ubicación'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickZone() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: widget.zones
              .map(
                (zone) => ListTile(
                  leading: Icon(Icons.location_city_rounded),
                  title: Text(
                    zone['city']?.toString() ?? 'Zona',
                  ),
                  subtitle: Text(
                    (zone['country']?.toString() ?? '') +
                        ' · ' +
                        (zone['currency_code']?.toString() ?? ''),
                  ),
                  trailing: selectedZoneId == zone['id']?.toString()
                      ? Icon(Icons.check_rounded, color: _dBlue)
                      : null,
                  onTap: () =>
                      Navigator.pop(context, zone['id']?.toString()),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (value != null) {
      setState(() {
        selectedZoneId = value;
        selectedAddressId = null;
      });
      try {
        final rows = await widget.service.marketplaceSavedAddressesV2(
          zoneId: value,
        );
        if (mounted) setState(() => addresses = rows);
      } catch (_) {}
    }
  }

  Future<void> _addAddress() async {
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: 'Nueva dirección',
          initialLabel: 'Mi ubicación actual',
          initialLatitude: widget.initialLatitude,
          initialLongitude: widget.initialLongitude,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final label = TextEditingController(text: 'Casa');
    final instructions = TextEditingController();
    bool makeDefault = true;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Guardar dirección'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: _dSoftBlue(context),
                      child: Icon(Icons.location_on_rounded, color: _dBlue),
                    ),
                    title: Text(
                      picked.label,
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      picked.latitude.toStringAsFixed(5) +
                          ', ' +
                          picked.longitude.toStringAsFixed(5),
                    ),
                  ),
                  TextField(
                    controller: label,
                    decoration: const InputDecoration(
                      labelText: 'Etiqueta',
                      hintText: 'Casa, Trabajo…',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: instructions,
                    decoration: const InputDecoration(
                      labelText: 'Indicaciones de entrega',
                      hintText: 'Ej. llamar al llegar',
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: makeDefault,
                    onChanged: (value) =>
                        setLocal(() => makeDefault = value),
                    title: Text('Dirección predeterminada'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      try {
        final row = await widget.service.marketplaceAddSavedAddressV2(
          label: label.text.trim(),
          address: picked.label,
          latitude: picked.latitude,
          longitude: picked.longitude,
          zoneId: selectedZoneId,
          instructions: instructions.text.trim(),
          makeDefault: makeDefault,
        );
        if (mounted) {
          setState(() {
            addresses.add(row);
            selectedAddressId = row['id']?.toString();
            selectedZoneId = row['zone_id']?.toString() ?? selectedZoneId;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
    label.dispose();
    instructions.dispose();
  }

}

class _DeliverySearchBar extends StatefulWidget {
  final String hint;
  final List<Map<String, dynamic>> merchants;
  final List<Map<String, dynamic>> products;
  final ValueChanged<Map<String, dynamic>> onMerchant;
  final ValueChanged<Map<String, dynamic>> onProduct;

  const _DeliverySearchBar({
    required this.hint,
    required this.merchants,
    required this.products,
    required this.onMerchant,
    required this.onProduct,
  });

  @override
  State<_DeliverySearchBar> createState() => _DeliverySearchBarState();
}

class _DeliverySearchBarState extends State<_DeliverySearchBar> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final merchants = normalized.isEmpty
        ? const <Map<String, dynamic>>[]
        : widget.merchants.where((row) {
            return [
              row['name'],
              row['description'],
              row['category_name'],
              row['search_terms'],
            ]
                .whereType<Object>()
                .map((e) => e.toString())
                .join(' ')
                .toLowerCase()
                .contains(normalized);
          }).take(6).toList();
    final products = normalized.isEmpty
        ? const <Map<String, dynamic>>[]
        : widget.products.where((row) {
            return [
              row['name'],
              row['merchant_name'],
              row['tags'],
            ]
                .whereType<Object>()
                .map((e) => e.toString())
                .join(' ')
                .toLowerCase()
                .contains(normalized);
          }).take(8).toList();

    return Column(
      children: [
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: Icon(Icons.search_rounded, color: _dBlue),
            filled: true,
            fillColor: _dSurface(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _dBorderColor(context)),
            ),
          ),
        ),
        if (normalized.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: _dSurface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _dBorderColor(context)),
            ),
            child: Column(
              children: [
                ...merchants.map(
                  (row) => ListTile(
                    dense: true,
                    leading: Icon(Icons.storefront_rounded),
                    title: Text(row['name']?.toString() ?? 'Local'),
                    subtitle: Text('Local'),
                    onTap: () => widget.onMerchant(row),
                  ),
                ),
                ...products.map(
                  (row) => ListTile(
                    dense: true,
                    leading: Icon(Icons.fastfood_rounded),
                    title: Text(row['name']?.toString() ?? 'Producto'),
                    subtitle:
                        Text(row['merchant_name']?.toString() ?? 'Producto'),
                    onTap: () => widget.onProduct(row),
                  ),
                ),
                if (merchants.isEmpty && products.isEmpty)
                  const ListTile(
                    title: Text('No encontramos resultados'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ModifierGroup extends StatelessWidget {
  final Map<String, dynamic> group;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String currency;

  const _ModifierGroup({
    required this.group,
    required this.selected,
    required this.onToggle,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final options = _dRows(group['options']);
    final min = _dNumber(group['min_select']).round();
    final max = _dNumber(group['max_select']).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _dSurface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _dBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group['name']?.toString() ?? 'Elige una opción',
                  style: TextStyle(
                    color: _dText(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                min > 0
                    ? 'Elige ' +
                        (min == max
                            ? min.toString()
                            : min.toString() + '-' + max.toString())
                    : 'Opcional',
                style: TextStyle(
                  color: _dMutedText(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if ((group['description']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              group['description'].toString(),
              style: TextStyle(color: _dMutedText(context), fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          ...options.map(
            (option) => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: selected.contains(option['id']?.toString()),
              onChanged: (_) => onToggle(option['id'].toString()),
              title: Text(option['name']?.toString() ?? 'Opción'),
              secondary: _dNumber(option['price_delta']) == 0
                  ? null
                  : Text(
                      '+ ' + _dMoney(option['price_delta'], currency),
                      style: TextStyle(
                        color: _dBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
        ],
      ),
    );
  }
}

class _MerchantCard extends StatelessWidget {
  final Map<String, dynamic> merchant;
  final VoidCallback onTap;

  const _MerchantCard({
    required this.merchant,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currency = merchant['currency_code']?.toString() ?? 'CLP';
    return Material(
      color: _dSurface(context),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _NetworkHero(
                  url: merchant['image_url']?.toString(),
                  icon: Icons.storefront_rounded,
                  height: 128,
                ),
                if (merchant['is_sponsored'] == true)
                  const Positioned(
                    left: 8,
                    top: 8,
                    child: _TinyTag(label: 'Anuncio'),
                  ),
                if (merchant['has_deals'] == true)
                  const Positioned(
                    right: 8,
                    top: 8,
                    child: _TinyTag(
                      label: 'PROMO',
                      highlighted: true,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant['name']?.toString() ?? 'Local',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _dText(context),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      _MiniPill(
                        icon: Icons.star_rounded,
                        label: (merchant['rating'] ?? '5.0').toString(),
                      ),
                      _MiniPill(
                        icon: Icons.schedule_rounded,
                        label:
                            (merchant['eta_min_minutes'] ?? 15).toString() +
                                '-' +
                                (merchant['eta_max_minutes'] ?? 40).toString() +
                                ' min',
                      ),
                      if (_dNumber(merchant['delivery_fee']) <= 0)
                        const _MiniPill(
                          icon: Icons.local_shipping_outlined,
                          label: 'Envío según zona',
                        )
                      else
                        _MiniPill(
                          icon: Icons.delivery_dining_rounded,
                          label: _dMoney(
                            merchant['delivery_fee'],
                            currency,
                          ),
                        ),
                      if (merchant['plus_enabled'] == true)
                        const _MiniPill(
                          icon: Icons.bolt_rounded,
                          label: 'Plus',
                          highlighted: true,
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
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currency = product['currency_code']?.toString() ?? 'CLP';
    final effective = _dNumber(
      product['effective_price'] ?? product['price'],
    );
    final regular = _dNumber(product['price']);
    final discount = _dNumber(product['discount_percent']).round();

    return Material(
      color: _dSurface(context),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _NetworkHero(
                  url: product['image_url']?.toString(),
                  icon: Icons.fastfood_rounded,
                  height: 122,
                ),
                if (product['is_sponsored'] == true)
                  const Positioned(
                    left: 7,
                    top: 7,
                    child: _TinyTag(label: 'Anuncio'),
                  ),
                if (discount > 0)
                  Positioned(
                    right: 7,
                    top: 7,
                    child: _TinyTag(
                      label: discount.toString() + '% DCTO',
                      highlighted: true,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name']?.toString() ?? 'Producto',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _dText(context),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product['merchant_name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _dMutedText(context),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _dMoney(effective, currency),
                    style: TextStyle(
                      color: _dBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (effective < regular)
                    Text(
                      _dMoney(regular, currency),
                      style: TextStyle(
                        color: _dMutedText(context),
                        fontSize: 10,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantProductRow extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  const _MerchantProductRow({
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currency = product['currency_code']?.toString() ?? 'CLP';
    final effective = _dNumber(product['effective_price']);
    final regular = _dNumber(product['price']);
    return Material(
      color: _dSurface(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 78,
                  height: 78,
                  child: _NetworkHero(
                    url: product['image_url']?.toString(),
                    icon: Icons.fastfood_rounded,
                    height: 78,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name']?.toString() ?? 'Producto',
                      style: TextStyle(
                        color: _dText(context),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if ((product['description']?.toString() ?? '').isNotEmpty)
                      Text(
                        product['description'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _dMutedText(context),
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          _dMoney(effective, currency),
                          style: TextStyle(
                            color: _dBlue,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (effective < regular) ...[
                          const SizedBox(width: 6),
                          Text(
                            _dMoney(regular, currency),
                            style: TextStyle(
                              color: _dMutedText(context),
                              fontSize: 10,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Ver producto',
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _dSoftBlue(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: _dBlue,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final rating = _dNumber(review['rating']).round();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < 5; i++)
                  Icon(
                    i < rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: const Color(0xFFFFB020),
                    size: 17,
                  ),
                const Spacer(),
                Text(
                  _dDate(review['created_at']),
                  style: TextStyle(color: _dMutedText(context), fontSize: 10),
                ),
              ],
            ),
            if ((review['comment']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                review['comment'].toString(),
                style: TextStyle(color: _dText(context), height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartQtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CartQtyButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 30,
        height: 28,
        child: Icon(
          icon,
          size: 17,
          color: _dText(context),
        ),
      ),
    );
  }
}

class _PaymentChoiceCard extends StatelessWidget {
  final String value;
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentChoiceCard({
    required this.value,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 160),
      scale: selected ? 1 : .97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 148,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _dSoftBlue(context) : _dSurfaceAlt(context),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? _dBlue : _dBorderColor(context),
            width: selected ? 1.7 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? _dBlue.withValues(alpha: .12)
                      : _dSurface(context),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  color: selected ? _dBlue : _dMutedText(context),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _dText(context),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _dMutedText(context),
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: _dBlue,
                  size: 17,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutCompactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CheckoutCompactAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _dSurface(context),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _dBorderColor(context)),
          ),
          child: Row(
            children: [
              Icon(icon, color: _dBlue, size: 19),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _dText(context),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: _dMutedText(context),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutMiniMap extends StatelessWidget {
  final double? storeLatitude;
  final double? storeLongitude;
  final double? userLatitude;
  final double? userLongitude;

  const _CheckoutMiniMap({
    required this.storeLatitude,
    required this.storeLongitude,
    required this.userLatitude,
    required this.userLongitude,
  });

  @override
  Widget build(BuildContext context) {
    if (storeLatitude == null ||
        storeLongitude == null ||
        userLatitude == null ||
        userLongitude == null) {
      return Container(
        height: 116,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _dSurfaceAlt(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _dBorderColor(context)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.map_outlined,
              color: _dBlue,
              size: 26,
            ),
            const SizedBox(height: 5),
            Text(
              'El mapa aparecerá al confirmar la ubicación',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _dMutedText(context),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    final store = LatLng(storeLatitude!, storeLongitude!);
    final user = LatLng(userLatitude!, userLongitude!);
    final center = LatLng(
      (store.latitude + user.latitude) / 2,
      (store.longitude + user.longitude) / 2,
    );
    final km = _distanceKm(
      store.latitude,
      store.longitude,
      user.latitude,
      user.longitude,
    );
    final zoom = km > 20
        ? 9.5
        : km > 10
            ? 10.5
            : km > 5
                ? 11.5
                : km > 2
                    ? 12.5
                    : 13.5;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 126,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.express.delivery',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [store, user],
                  color: _dBlue,
                  strokeWidth: 3,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: store,
                  width: 38,
                  height: 38,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _dSurface(context),
                      shape: BoxShape.circle,
                      border: Border.all(color: _dBlue, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: _dBlue,
                      size: 20,
                    ),
                  ),
                ),
                Marker(
                  point: user,
                  width: 38,
                  height: 38,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _dBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person_pin_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryQuickDrawer extends StatelessWidget {
  final VoidCallback? onRide;
  final VoidCallback? onRestaurant;
  final VoidCallback? onDriver;
  final VoidCallback? onServices;

  const _DeliveryQuickDrawer({
    this.onRide,
    this.onRestaurant,
    this.onDriver,
    this.onServices,
  });

  void _closeThen(BuildContext context, VoidCallback? action) {
    Navigator.pop(context);
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 284,
      backgroundColor: _dSurface(context),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _dBlue,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EXPRESS',
                          style: TextStyle(
                            color: _dText(context),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Accesos rápidos',
                          style: TextStyle(
                            color: _dMutedText(context),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _QuickDrawerTile(
                icon: Icons.local_taxi_rounded,
                title: 'Viajes Express',
                subtitle: 'Solicitar moto o auto',
                onTap: () => _closeThen(context, onRide),
              ),
              const SizedBox(height: 8),
              _QuickDrawerTile(
                icon: Icons.restaurant_rounded,
                title: 'Restaurantes',
                subtitle: 'Express Delivery',
                selected: true,
                onTap: () => _closeThen(context, onRestaurant),
              ),
              const SizedBox(height: 8),
              _QuickDrawerTile(
                icon: Icons.delivery_dining_rounded,
                title: 'Conductor',
                subtitle: 'Cambiar al modo conductor',
                onTap: () => _closeThen(context, onDriver),
              ),
              const Spacer(),
              if (onServices != null)
                _QuickDrawerTile(
                  icon: Icons.apps_rounded,
                  title: 'Todos los servicios',
                  subtitle: 'Volver al selector principal',
                  onTap: () => _closeThen(context, onServices),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickDrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _QuickDrawerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _dSoftBlue(context) : _dSurfaceAlt(context),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? _dBlue.withValues(alpha: .12)
                      : _dSurface(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: selected ? _dBlue : _dMutedText(context),
                  size: 20,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _dText(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _dMutedText(context),
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? _dBlue : _dMutedText(context),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutBlock extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _CheckoutBlock({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _dSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _dBlue, size: 20),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: _dText(context),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _NetworkHero extends StatelessWidget {
  final String? url;
  final IconData icon;
  final double height;

  const _NetworkHero({
    required this.url,
    required this.icon,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final value = url?.trim() ?? '';
    if (value.isEmpty) {
      return Container(
        height: height,
        width: double.infinity,
        color: _dSoftBlue(context),
        alignment: Alignment.center,
        child: Icon(icon, color: _dBlue, size: 42),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Image.network(
        value,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: _dSoftBlue(context),
          alignment: Alignment.center,
          child: Icon(icon, color: _dBlue, size: 42),
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;

  const _MiniPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? _dSoftBlue(context)
            : _dSurfaceAlt(context),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: highlighted ? _dBlue : _dMutedText(context),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: highlighted ? _dBlue : _dText(context),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyTag extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _TinyTag({
    required this.label,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFF14804A) : _dSurface(context),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted ? Colors.white : _dText(context),
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionTitle({
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _dText(context),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            style: TextStyle(color: _dMutedText(context), fontSize: 11),
          ),
      ],
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _DeliveryHomeSkeleton extends StatelessWidget {
  const _DeliveryHomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _Skeleton(height: 70),
        SizedBox(height: 12),
        _Skeleton(height: 38, width: 260),
        SizedBox(height: 8),
        _Skeleton(height: 50),
        SizedBox(height: 14),
        _Skeleton(height: 150),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _Skeleton(height: 90)),
            SizedBox(width: 8),
            Expanded(child: _Skeleton(height: 90)),
          ],
        ),
        SizedBox(height: 16),
        _Skeleton(height: 220),
      ],
    );
  }
}

class _DeliveryListSkeleton extends StatelessWidget {
  const _DeliveryListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _Skeleton(height: 110),
        SizedBox(height: 10),
        _Skeleton(height: 110),
        SizedBox(height: 10),
        _Skeleton(height: 110),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double height;
  final double? width;

  const _Skeleton({
    required this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: _dDark(context)
            ? const Color(0xFF1D2733)
            : const Color(0xFFE9EDF3),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}

class _DeliveryEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _DeliveryEmpty({
    required this.icon,
    required this.title,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _dSurface(context),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _dBlue, size: 42),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _dText(context),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: _dMutedText(context), height: 1.35),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeliveryError extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;

  const _DeliveryError({
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return _DeliveryEmpty(
      icon: Icons.error_outline_rounded,
      title: 'No pudimos cargar Express Delivery',
      text: error,
      actionLabel: onRetry == null ? null : 'Reintentar',
      onAction: onRetry,
    );
  }
}

IconData _deliveryCategoryIcon(String? key) {
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

IconData _notificationIcon(String? type) {
  switch (type) {
    case 'marketplace_promo':
      return Icons.local_offer_rounded;
    case 'marketplace_plus':
      return Icons.bolt_rounded;
    case 'marketplace_order':
      return Icons.receipt_long_rounded;
    default:
      return Icons.notifications_rounded;
  }
}

String _orderStatusLabel(String status) {
  switch (status) {
    case 'awaiting_transfer':
      return 'Esperando transferencia';
    case 'payment_review':
      return 'Verificando pago';
    case 'confirmed':
      return 'Pedido confirmado';
    case 'preparing':
      return 'Preparando';
    case 'ready':
      return 'Listo para retiro';
    case 'searching_driver':
      return 'Buscando repartidor';
    case 'driver_assigned':
      return 'Repartidor asignado';
    case 'picked_up':
      return 'Retirado del local';
    case 'delivering':
      return 'En camino';
    case 'delivered':
      return 'Entregado';
    case 'cancelled':
      return 'Cancelado';
    default:
      return 'Pedido recibido';
  }
}

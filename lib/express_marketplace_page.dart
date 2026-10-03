import 'package:flutter/material.dart';

import 'services/express_service.dart';

class ExpressMarketplacePage extends StatefulWidget {
  final ExpressService service;

  const ExpressMarketplacePage({
    super.key,
    required this.service,
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

  @override
  void initState() {
    super.initState();
    future = widget.service.marketplaceHome();
  }

  void _refresh() {
    setState(() {
      future = widget.service.marketplaceHome();
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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, color: _blue),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              settings['search_placeholder']?.toString() ??
                                  'Locales, productos y promociones',
                              style: const TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: _blue,
                          ),
                        ],
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
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {},
                        child: Padding(
                          padding: const EdgeInsets.all(15),
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
                const Text(
                  'Locales',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (merchants.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.store_mall_directory_outlined, color: _blue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Todavía no hay comercios cargados en esta zona. Puedes agregarlos desde el panel administrativo.',
                            style: TextStyle(color: _muted, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...merchants.map(
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

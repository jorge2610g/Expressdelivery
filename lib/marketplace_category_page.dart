import 'package:flutter/material.dart';

class MarketplaceCategoryPage extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> merchants;
  final Map<String, dynamic> initialCategory;
  final ValueChanged<Map<String, dynamic>> onMerchantTap;

  const MarketplaceCategoryPage({
    super.key,
    required this.categories,
    required this.merchants,
    required this.initialCategory,
    required this.onMerchantTap,
  });

  @override
  State<MarketplaceCategoryPage> createState() =>
      _MarketplaceCategoryPageState();
}

class _MarketplaceCategoryPageState extends State<MarketplaceCategoryPage> {
  static const blue = Color(0xFF1769E0);
  static const ink = Color(0xFF101828);
  static const muted = Color(0xFF667085);
  static const surface = Color(0xFFF6F8FC);

  late String selectedKey;
  final searchController = TextEditingController();
  String search = '';

  @override
  void initState() {
    super.initState();
    selectedKey =
        widget.initialCategory['category_key']?.toString() ?? '';
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
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

  Map<String, dynamic> get selectedCategory {
    return widget.categories.firstWhere(
      (row) => row['category_key']?.toString() == selectedKey,
      orElse: () => widget.initialCategory,
    );
  }

  List<Map<String, dynamic>> get visibleMerchants {
    final query = search.trim().toLowerCase();
    return widget.merchants.where((merchant) {
      if (merchant['category_key']?.toString() != selectedKey) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        merchant['name'],
        merchant['description'],
        merchant['search_terms'],
      ].whereType<Object>().map((value) => value.toString()).join(' ');
      return haystack.toLowerCase().contains(query);
    }).toList();
  }

  Widget _merchantImage(Map<String, dynamic> merchant) {
    final url = merchant['image_url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      return Container(
        color: const Color(0xFFEAF2FF),
        alignment: Alignment.center,
        child: const Icon(
          Icons.storefront_rounded,
          color: blue,
          size: 42,
        ),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFFEAF2FF),
        alignment: Alignment.center,
        child: const Icon(
          Icons.storefront_rounded,
          color: blue,
          size: 42,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = selectedCategory;
    final merchants = visibleMerchants;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: Text(
          category['name']?.toString() ?? 'Express Delivery',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final row = widget.categories[index];
                final key = row['category_key']?.toString() ?? '';
                final selected = key == selectedKey;

                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() {
                    selectedKey = key;
                    search = '';
                    searchController.clear();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 92,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? blue : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? blue
                            : const Color(0xFFE4E7EC),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _icon(row['icon_key']?.toString()),
                          color: selected ? Colors.white : blue,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          row['name']?.toString() ?? 'Categoría',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.white : ink,
                            fontSize: 11,
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
          const SizedBox(height: 16),
          Text(
            category['name']?.toString() ?? 'Locales',
            style: const TextStyle(
              color: ink,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            merchants.isEmpty
                ? 'Todavía no hay locales disponibles en esta categoría.'
                : merchants.length.toString() +
                    (merchants.length == 1
                        ? ' local disponible'
                        : ' locales disponibles'),
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: searchController,
            onChanged: (value) => setState(() => search = value),
            decoration: InputDecoration(
              hintText: 'Buscar en esta categoría',
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
          const SizedBox(height: 18),
          if (merchants.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.store_mall_directory_outlined,
                    size: 42,
                    color: blue,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Sin locales por ahora',
                    style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Cuando se agreguen restaurantes o tiendas a esta categoría aparecerán aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, height: 1.35),
                  ),
                ],
              ),
            )
          else
            ...merchants.map(
              (merchant) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => widget.onMerchantTap(merchant),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 138,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _merchantImage(merchant),
                              Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      '★ ' +
                                          (merchant['rating'] ?? '5.0')
                                              .toString(),
                                      style: const TextStyle(
                                        color: ink,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      merchant['name']?.toString() ??
                                          'Local',
                                      style: const TextStyle(
                                        color: ink,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: muted,
                                  ),
                                ],
                              ),
                              if ((merchant['description']
                                          ?.toString()
                                          .trim() ??
                                      '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  merchant['description'].toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _InfoPill(
                                    icon: Icons.schedule_rounded,
                                    label:
                                        '${merchant['eta_min_minutes'] ?? 15}-${merchant['eta_max_minutes'] ?? 40} min',
                                  ),
                                  if (merchant['plus_enabled'] == true)
                                    const _InfoPill(
                                      icon: Icons.bolt_rounded,
                                      label: 'Express Plus',
                                      highlight: true,
                                    ),
                                  if (merchant['plus_free_delivery'] == true)
                                    const _InfoPill(
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
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;

  const _InfoPill({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
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
          Icon(
            icon,
            size: 14,
            color: highlight ? blue : muted,
          ),
          const SizedBox(width: 4),
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

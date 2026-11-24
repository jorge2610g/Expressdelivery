import 'package:flutter/material.dart';

import 'core/runtime_channel.dart';
import 'services/express_service.dart';

/// Avisos de la empresa: invitaciones, novedades y comunicados que el usuario
/// puede abrir cuando quiera. La notificación push solo avisa; el contenido
/// vive aquí hasta que el aviso caduca.

class AvisoCategory {
  final String label;
  final IconData icon;
  final Color color;

  const AvisoCategory(this.label, this.icon, this.color);

  static const _all = <String, AvisoCategory>{
    'aviso': AvisoCategory('Aviso', Icons.campaign_outlined, Color(0xFF0B57D0)),
    'evento': AvisoCategory('Evento', Icons.celebration_outlined, Color(0xFF7C3AED)),
    'importante':
        AvisoCategory('Importante', Icons.priority_high_rounded, Color(0xFFD92D20)),
    'novedad': AvisoCategory('Novedad', Icons.auto_awesome_outlined, Color(0xFF15803D)),
  };

  static AvisoCategory of(Object? key) =>
      _all[key?.toString()] ?? _all['aviso']!;

  static Map<String, AvisoCategory> get all => _all;
}

String avisoDate(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

/// Texto de caducidad: «Se elimina el 24/12/2026», o vacío si no caduca.
String avisoExpiryNote(Object? expiresAt) {
  final date = avisoDate(expiresAt);
  return date.isEmpty ? '' : 'Este aviso se elimina automáticamente el $date.';
}

enum _AvisoFilter { all, unread, aviso, evento, importante, novedad }

/// Lista de avisos con filtros. `openId` abre ese aviso apenas carga
/// (toque en la notificación push).
class AvisosList extends StatefulWidget {
  final ExpressService service;
  final String? openId;

  const AvisosList({super.key, required this.service, this.openId});

  @override
  State<AvisosList> createState() => _AvisosListState();
}

class _AvisosListState extends State<AvisosList> {
  late Future<List<Map<String, dynamic>>> future;
  _AvisoFilter filter = _AvisoFilter.all;
  bool openedRequested = false;

  @override
  void initState() {
    super.initState();
    future = widget.service.myAnnouncements();
  }

  void _reload() {
    setState(() => future = widget.service.myAnnouncements());
  }

  Future<void> _open(Map<String, dynamic> aviso) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AvisoDetailPage(service: widget.service, aviso: aviso),
      ),
    );
    if (mounted) _reload();
  }

  void _maybeOpenRequested(List<Map<String, dynamic>> rows) {
    final id = widget.openId;
    if (id == null || id.isEmpty || openedRequested) return;
    openedRequested = true;
    final match = rows.where((row) => row['id']?.toString() == id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (match.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este aviso ya no está disponible.')),
        );
        return;
      }
      _open(match.first);
    });
  }

  bool _matches(Map<String, dynamic> row) {
    switch (filter) {
      case _AvisoFilter.all:
        return true;
      case _AvisoFilter.unread:
        return row['is_read'] != true;
      case _AvisoFilter.aviso:
        return row['category'] == 'aviso';
      case _AvisoFilter.evento:
        return row['category'] == 'evento';
      case _AvisoFilter.importante:
        return row['category'] == 'importante';
      case _AvisoFilter.novedad:
        return row['category'] == 'novedad';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ExpressRuntimeChannel.userSafeError(
                      snapshot.error,
                      fallback: 'No se pudieron cargar los avisos.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }
        final all = snapshot.data ?? const <Map<String, dynamic>>[];
        _maybeOpenRequested(all);
        final rows = all.where(_matches).toList();
        final scheme = Theme.of(context).colorScheme;

        final chips = <(_AvisoFilter, String)>[
          (_AvisoFilter.all, 'Todos'),
          (_AvisoFilter.unread, 'Sin leer'),
          (_AvisoFilter.aviso, 'Avisos'),
          (_AvisoFilter.evento, 'Eventos'),
          (_AvisoFilter.importante, 'Importantes'),
          (_AvisoFilter.novedad, 'Novedades'),
        ];

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final chip in chips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(chip.$2),
                          selected: filter == chip.$1,
                          onSelected: (_) => setState(() => filter = chip.$1),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(
                        Icons.campaign_outlined,
                        size: 56,
                        color: scheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        all.isEmpty
                            ? 'No tienes avisos'
                            : 'No hay avisos en este filtro',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Aquí verás eventos, novedades y comunicados de Express.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                for (final row in rows)
                  _AvisoCard(aviso: row, onTap: () => _open(row)),
              if (rows.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Los avisos se eliminan solos cuando llega la fecha indicada en cada uno.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
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

class _AvisoCard extends StatelessWidget {
  final Map<String, dynamic> aviso;
  final VoidCallback onTap;

  const _AvisoCard({required this.aviso, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = AvisoCategory.of(aviso['category']);
    final unread = aviso['is_read'] != true;
    final image = aviso['image_url']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unread ? category.color.withValues(alpha: 0.5) : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: image.isEmpty
                      ? _CategoryTile(category: category)
                      : Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _CategoryTile(category: category),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _CategoryTag(category: category),
                        const Spacer(),
                        Text(
                          avisoDate(aviso['publish_at']),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            aviso['title']?.toString() ?? 'Aviso',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  unread ? FontWeight.w900 : FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (unread)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.circle,
                              size: 9,
                              color: category.color,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      aviso['body']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final AvisoCategory category;
  const _CategoryTile({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: category.color.withValues(alpha: 0.12),
      child: Icon(category.icon, color: category.color, size: 32),
    );
  }
}

class _CategoryTag extends StatelessWidget {
  final AvisoCategory category;
  const _CategoryTag({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        category.label,
        style: TextStyle(
          color: category.color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Pantalla completa del menú «Avisos».
class AvisosPage extends StatelessWidget {
  final ExpressService service;
  final String? openId;

  const AvisosPage({super.key, required this.service, this.openId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Avisos')),
      body: AvisosList(service: service, openId: openId),
    );
  }
}

class AvisoDetailPage extends StatefulWidget {
  final ExpressService service;
  final Map<String, dynamic> aviso;

  const AvisoDetailPage({
    super.key,
    required this.service,
    required this.aviso,
  });

  @override
  State<AvisoDetailPage> createState() => _AvisoDetailPageState();
}

class _AvisoDetailPageState extends State<AvisoDetailPage> {
  @override
  void initState() {
    super.initState();
    if (widget.aviso['is_read'] != true) {
      widget.service
          .markAnnouncementRead(widget.aviso['id'].toString())
          .catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aviso = widget.aviso;
    final category = AvisoCategory.of(aviso['category']);
    final image = aviso['image_url']?.toString() ?? '';
    final expiry = avisoExpiryNote(aviso['expires_at']);
    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (image.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          Row(
            children: [
              _CategoryTag(category: category),
              const SizedBox(width: 10),
              Text(
                avisoDate(aviso['publish_at']),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            aviso['title']?.toString() ?? 'Aviso',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          SelectableText(
            aviso['body']?.toString() ?? '',
            style: const TextStyle(fontSize: 15, height: 1.45),
          ),
          if (expiry.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      expiry,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Entrada «Avisos» de los menús con contador de no leídos.
class AvisosMenuTile extends StatelessWidget {
  final ExpressService service;
  final VoidCallback onTap;

  const AvisosMenuTile({super.key, required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: service.unreadAnnouncementsCount(),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return ListTile(
          leading: const Icon(Icons.campaign_outlined),
          title: const Text('Avisos'),
          subtitle: const Text('Eventos, novedades y comunicados'),
          trailing: unread > 0
              ? CircleAvatar(
                  radius: 12,
                  backgroundColor: const Color(0xFFD92D20),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : null,
          onTap: onTap,
        );
      },
    );
  }
}

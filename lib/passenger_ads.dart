import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'services/express_service.dart';

/// Tarjeta de anuncio propio dentro de una pantalla del pasajero.
///
/// [placement] indica el lugar: `map_home` (panel «¿A dónde vas?») o
/// `ride_chooser` (tarjeta de «¿A dónde y por cuánto?»). Supabase decide qué
/// anuncios ve cada cuenta; si no hay ninguno, el widget no ocupa espacio.
class PassengerAdSlot extends StatefulWidget {
  final ExpressService service;
  final String? zoneId;
  final String placement;

  const PassengerAdSlot({
    super.key,
    required this.service,
    required this.zoneId,
    required this.placement,
  });

  @override
  State<PassengerAdSlot> createState() => _PassengerAdSlotState();
}

class _PassengerAdSlotState extends State<PassengerAdSlot> {
  static const double _cardHeight = 318;

  final PageController _pages = PageController();
  List<Map<String, dynamic>> _ads = const [];
  int _index = 0;
  int _requestId = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PassengerAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoneId != widget.zoneId ||
        oldWidget.placement != widget.placement) {
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_requestId;
    List<Map<String, dynamic>> ads;
    try {
      ads = await widget.service.passengerAds(widget.zoneId, widget.placement);
    } catch (_) {
      // Los anuncios son opcionales: si fallan, la pantalla sigue igual.
      ads = const <Map<String, dynamic>>[];
    }
    if (!mounted || request != _requestId) return;
    setState(() {
      _ads = ads;
      _index = 0;
    });
    _schedule();
  }

  int _seconds(Map<String, dynamic> row) {
    final raw = row['display_seconds'];
    final value =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 5;
    return value.clamp(3, 60);
  }

  void _schedule() {
    _timer?.cancel();
    if (_ads.length < 2) return;
    final current = _ads[_index.clamp(0, _ads.length - 1)];
    _timer = Timer(Duration(seconds: _seconds(current)), () {
      if (!mounted || !_pages.hasClients) return;
      _pages.animateToPage(
        (_index + 1) % _ads.length,
        duration: const Duration(milliseconds: 370),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _open(Map<String, dynamic> ad) async {
    // Solo los enlaces externos se abren desde aquí. Los destinos de módulo
    // no aplican en esta pantalla y el anuncio se queda como está.
    final url = Uri.tryParse((ad['target_url'] ?? '').toString());
    if (url == null || !url.hasScheme) return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_ads.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _cardHeight,
          child: PageView.builder(
            controller: _pages,
            itemCount: _ads.length,
            onPageChanged: (value) {
              setState(() => _index = value);
              _schedule();
            },
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _AdCard(
                ad: _ads[i],
                active: i == _index,
                surface: scheme.surface,
                ink: scheme.onSurface,
                onTap: () => _open(_ads[i]),
              ),
            ),
          ),
        ),
        if (_ads.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _ads.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _index
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AdCard extends StatelessWidget {
  final Map<String, dynamic> ad;
  final bool active;
  final Color surface;
  final Color ink;
  final VoidCallback onTap;

  const _AdCard({
    required this.ad,
    required this.active,
    required this.surface,
    required this.ink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = (ad['title'] ?? '').toString();
    final subtitle = (ad['subtitle'] ?? '').toString();
    final advertiser = (ad['advertiser_name'] ?? '').toString();
    final cta = (ad['cta_label'] ?? '').toString();
    final imageUrl = (ad['image_url'] ?? '').toString();
    final mediaUrl = (ad['media_url'] ?? '').toString();
    final isVideo =
        ad['media_type'] == 'video' && mediaUrl.startsWith('https://');

    final media = isVideo
        ? _AdVideo(url: mediaUrl, active: active)
        : imageUrl.startsWith('https://')
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _AdFallback(),
              )
            : const _AdFallback();

    return Material(
      color: surface,
      elevation: 2,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  media,
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x99000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Ad',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (advertiser.isNotEmpty)
                      Text(
                        advertiser,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                      ),
                    const Spacer(),
                    if (cta.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: ink,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            child: Text(
                              cta,
                              style: TextStyle(
                                color: surface,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdFallback extends StatelessWidget {
  const _AdFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF1B2A41));
  }
}

/// Video corto, silenciado y en bucle. Solo reproduce cuando la tarjeta es la
/// visible, para no gastar datos ni batería con anuncios fuera de pantalla.
class _AdVideo extends StatefulWidget {
  final String url;
  final bool active;

  const _AdVideo({required this.url, required this.active});

  @override
  State<_AdVideo> createState() => _AdVideoState();
}

class _AdVideoState extends State<_AdVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    controller
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _syncPlayback();
      }).catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant _AdVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPlayback();
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.active) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) return const _AdFallback();
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

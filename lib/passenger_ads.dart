import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'services/express_service.dart';
import 'express_ad_live_updates.dart';
import 'banner_creatives.dart';

Future<void> showPassengerPopupAds(
  BuildContext context, {
  required ExpressService service,
  required String? zoneId,
}) async {
  if (zoneId == null || zoneId.isEmpty || !context.mounted) return;
  List<Map<String, dynamic>> ads;
  try {
    ads = bannerCreatives(await service.passengerAds(zoneId, 'popup'));
  } catch (_) {
    return;
  }
  if (ads.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExpressAdPopup(service: service, zoneId: zoneId, ads: ads),
  );
}

class _ExpressAdPopup extends StatefulWidget {
  final ExpressService service;
  final String zoneId;
  final List<Map<String, dynamic>> ads;
  const _ExpressAdPopup({
    required this.service,
    required this.zoneId,
    required this.ads,
  });

  @override
  State<_ExpressAdPopup> createState() => _ExpressAdPopupState();
}

class _ExpressAdPopupState extends State<_ExpressAdPopup> {
  late List<Map<String, dynamic>> _ads = widget.ads;
  ExpressAdLiveUpdates? _live;
  final PageController _controller = PageController();
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _record('impression');
    _schedule();
    _live = ExpressAdLiveUpdates(widget.zoneId, _reload);
  }

  Future<void> _reload() async {
    try {
      final rows = bannerCreatives(
        await widget.service.passengerAds(widget.zoneId, 'popup'),
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
        return;
      }
      final key = _ads[_index]['creative_key'];
      final retained = rows.indexWhere((row) => row['creative_key'] == key);
      setState(() {
        _ads = rows;
        _index = retained < 0 ? 0 : retained;
      });
      if (_controller.hasClients) _controller.jumpToPage(_index);
      if (_timer?.isActive != true) _schedule();
    } catch (_) {
      /* Keep the last authorized creative on a transient outage. */
    }
  }

  void _record(String type) {
    final id = _ads[_index]['id']?.toString() ?? '';
    if (id.isEmpty) return;
    unawaited(
      widget.service
          .recordExpressAdEvent(
            bannerId: id,
            zoneId: widget.zoneId,
            placement: 'popup',
            eventType: type,
          )
          .catchError((_) {}),
    );
  }

  void _schedule() {
    _timer?.cancel();
    if (_ads.length < 2) return;
    final raw = _ads[_index]['display_seconds'];
    final secs = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 5;
    _timer = Timer(Duration(seconds: secs.clamp(3, 60)), () {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_index + 1) % _ads.length,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _live?.dispose();
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: _ads.length,
          onPageChanged: (i) {
            setState(() => _index = i);
            _record('impression');
            _schedule();
          },
          itemBuilder: (context, i) {
            final ad = _ads[i];
            final image = ad['image_url']?.toString() ?? '';
            final video = ad['media_url']?.toString() ?? '';
            final isVideo =
                ad['media_type'] == 'video' && video.startsWith('https://');
            return GestureDetector(
              onTap: () async {
                _record('click');
                final uri = Uri.tryParse(ad['target_url']?.toString() ?? '');
                if (uri != null && uri.scheme == 'https')
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: isVideo
                  ? _AdVideo(
                      key: ValueKey(video),
                      url: video,
                      active: i == _index,
                    )
                  : image.startsWith('https://')
                  ? Image.network(
                      image,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                  : const ColoredBox(color: Colors.black12),
            );
          },
        ),
        Positioned(
          right: 8,
          top: 8,
          child: IconButton.filledTonal(
            tooltip: 'Cerrar anuncio',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    ),
  );
}

/// Tarjeta de anuncio propio dentro de una pantalla del pasajero.
///
/// [placement] indica el lugar: `map_home` (panel «¿A dónde vas?») o
/// `ride_chooser` (tarjeta de «¿A dónde y por cuánto?»). Supabase decide qué
/// anuncios ve cada cuenta; si no hay ninguno, el widget no ocupa espacio.
class PassengerAdSlot extends StatefulWidget {
  final ExpressService service;
  final String? zoneId;
  final String placement;

  /// `driver` uses the driver's approved profile and zone on the server.
  final String audience;
  // Tarjeta baja para hojas de altura fija (selector de viaje).
  final bool compact;

  const PassengerAdSlot({
    super.key,
    required this.service,
    required this.zoneId,
    required this.placement,
    this.audience = 'passenger',
    this.compact = false,
  });

  @override
  State<PassengerAdSlot> createState() => _PassengerAdSlotState();
}

class _PassengerAdSlotState extends State<PassengerAdSlot>
    with WidgetsBindingObserver {
  ExpressAdLiveUpdates? _live;
  List<Map<String, dynamic>> _ads = const [];
  int _index = 0;
  int _requestId = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watch();
    _load();
  }

  void _watch() {
    _live?.dispose();
    final zone = widget.zoneId;
    if (zone != null && zone.isNotEmpty) {
      _live = ExpressAdLiveUpdates(zone, () {
        if (mounted) _load();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void didUpdateWidget(covariant PassengerAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoneId != widget.zoneId ||
        oldWidget.placement != widget.placement ||
        oldWidget.audience != widget.audience) {
      _watch();
      _load(clear: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool clear = false}) async {
    final request = ++_requestId;
    // Al cambiar de zona no se deben ver ni tocar anuncios de la zona anterior.
    if (clear) _timer?.cancel();
    if (clear && _ads.isNotEmpty) {
      setState(() {
        _ads = const [];
        _index = 0;
      });
    }
    List<Map<String, dynamic>> ads;
    try {
      ads = widget.audience == 'driver'
          ? await widget.service.driverAds(widget.zoneId, widget.placement)
          : await widget.service.passengerAds(widget.zoneId, widget.placement);
    } catch (_) {
      // Los anuncios son opcionales: si fallan, la pantalla sigue igual.
      if (mounted && request == _requestId && _timer?.isActive != true)
        _schedule();
      return;
    }
    if (!mounted || request != _requestId) return;
    final previousId = _ads.isEmpty ? null : _ads[_index]['creative_key'];
    final previousSeconds = _ads.isEmpty ? null : _seconds(_ads[_index]);
    setState(() {
      _ads = bannerCreatives(ads);
      final retained = _ads.indexWhere(
        (ad) => ad['creative_key'] == previousId,
      );
      _index = retained < 0 ? 0 : retained;
    });
    if (_ads.isNotEmpty) _record(_ads[_index], 'impression');
    if (_ads.isEmpty ||
        _ads.length < 2 ||
        previousId != _ads[_index]['creative_key'] ||
        previousSeconds != _seconds(_ads[_index]) ||
        _timer?.isActive != true) {
      _schedule();
    }
  }

  void _record(Map<String, dynamic> ad, String eventType) {
    final id = ad['id']?.toString() ?? '';
    final zone = widget.zoneId;
    if (id.isEmpty || zone == null || zone.isEmpty) return;
    unawaited(
      widget.service
          .recordExpressAdEvent(
            bannerId: id,
            zoneId: zone,
            placement: widget.placement,
            eventType: eventType,
          )
          .catchError((_) {}),
    );
  }

  int _seconds(Map<String, dynamic> row) {
    final raw = row['display_seconds'];
    final value = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '') ?? 5;
    return value.clamp(3, 60);
  }

  void _schedule() {
    _timer?.cancel();
    if (_ads.length < 2) return;
    final current = _ads[_index.clamp(0, _ads.length - 1)];
    _timer = Timer(Duration(seconds: _seconds(current)), () {
      if (!mounted) return;
      _show((_index + 1) % _ads.length);
    });
  }

  void _show(int index) {
    setState(() => _index = index);
    _record(_ads[index], 'impression');
    _schedule();
  }

  Future<void> _open(Map<String, dynamic> ad) async {
    // Solo los enlaces externos se abren desde aquí. Los destinos de módulo
    // no aplican en esta pantalla y el anuncio se queda como está.
    final url = Uri.tryParse((ad['target_url'] ?? '').toString());
    if (url == null || url.scheme != 'https') return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_ads.isEmpty) return const SizedBox.shrink();
    final ad = _ads[_index];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onHorizontalDragEnd: _ads.length < 2
              ? null
              : (details) {
                  final direction = (details.primaryVelocity ?? 0) < 0 ? 1 : -1;
                  _show((_index + direction) % _ads.length);
                },
          child: AnimatedSize(
            duration: const Duration(milliseconds: 240),
            alignment: Alignment.topCenter,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
                layoutBuilder: (current, previous) => Stack(
                  children: [
                    if (current != null) current,
                    for (final child in previous) Positioned.fill(child: child),
                  ],
                ),
                child: Semantics(
                  key: ValueKey(ad['creative_key']),
                  label: 'Banner publicitario',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      _record(ad, 'click');
                      _open(ad);
                    },
                    child:
                        ad['media_type'] == 'video' &&
                            (ad['media_url'] ?? '').toString().startsWith(
                              'https://',
                            )
                        ? ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: inlineBannerMaxHeight(context),
                            ),
                            child: _AdVideo(
                              key: ValueKey(ad['media_url']),
                              url: ad['media_url'].toString(),
                              active: true,
                              fixedBannerFrame: true,
                              frameAspectRatio:
                                  bannerAspectRatioForPlacement(
                                    widget.placement,
                                  ),
                            ),
                          )
                        : ExpressBannerImage(
                            key: ValueKey(ad['image_url']),
                            image: NetworkImage(ad['image_url'].toString()),
                            aspectRatio:
                                bannerAspectRatioForPlacement(widget.placement),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_ads.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _ads.length; i++)
                Semantics(
                  button: true,
                  label: 'Banner ${i + 1} de ${_ads.length}',
                  child: InkWell(
                    onTap: () => _show(i),
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 12,
                      height: 20,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: i == _index ? 7 : 5,
                          height: i == _index ? 7 : 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _index
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Inline ads use their placement's fixed frame and leave room for the map.
double inlineBannerMaxHeight(BuildContext context) =>
    math.min(180, MediaQuery.sizeOf(context).height * .20);

/// Returns the display ratio advertised to the panel for this placement.
double bannerAspectRatioForPlacement(String placement) =>
    placement == 'popup' ? 9 / 16 : 3.2;

/// Fills the placement's standard frame without distorting the creative.
class ExpressBannerImage extends StatelessWidget {
  final ImageProvider image;
  final double aspectRatio;
  const ExpressBannerImage({
    super.key,
    required this.image,
    this.aspectRatio = 3.2,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = math.min(
        constraints.maxWidth / aspectRatio,
        inlineBannerMaxHeight(context),
      );
      return SizedBox(
        width: constraints.maxWidth,
        height: height,
        child: Image(
          image: image,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const _AdFallback(),
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    },
  );
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
  final bool fixedBannerFrame;
  final double frameAspectRatio;

  const _AdVideo({
    super.key,
    required this.url,
    required this.active,
    this.fixedBannerFrame = false,
    this.frameAspectRatio = 3.2,
  });

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
      ..initialize()
          .then((_) {
            if (!mounted) return;
            setState(() => _ready = true);
            _syncPlayback();
          })
          .catchError((_) {});
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
    if (!_ready || controller == null) {
      return const AspectRatio(aspectRatio: 3.2, child: _AdFallback());
    }
    if (!widget.fixedBannerFrame) {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(
          constraints.maxWidth / widget.frameAspectRatio,
          inlineBannerMaxHeight(context),
        );
        return SizedBox(
          width: constraints.maxWidth,
          height: height,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxWidth / controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        );
      },
    );
  }
}

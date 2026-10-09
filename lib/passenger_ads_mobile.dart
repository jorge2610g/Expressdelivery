import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/runtime_channel.dart';
import 'passenger_ads_policy.dart';

class ExpressPassengerAds {
  const ExpressPassengerAds._();

  static const String _productionBannerUnitId =
      String.fromEnvironment('ADMOB_PASSENGER_BANNER_UNIT_ID');
  static const String _googleAndroidTestBannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  static Future<void>? _initialization;

  /// Ad unit IDs are public identifiers. The backend may update a production
  /// Banner ID without rebuilding, but Android's AdMob App ID in the manifest
  /// still requires a signed APK build. Preview ALWAYS uses Google's test ID.
  static String bannerUnitId(Map<String, dynamic> settings) {
    if (ExpressRuntimeChannel.previewMode) return _googleAndroidTestBannerUnitId;
    final remote =
        settings['admob_passenger_banner_unit_id']?.toString().trim() ?? '';
    if (RegExp(r'^ca-app-pub-[0-9]{16}/[0-9]{10}
}

class PassengerAdSlot extends StatefulWidget {
  final Map<String, dynamic> settings;
  final PassengerAdPlacement placement;

  const PassengerAdSlot({
    super.key,
    required this.settings,
    required this.placement,
  });

  @override
  State<PassengerAdSlot> createState() => _PassengerAdSlotState();
}

class _PassengerAdSlotState extends State<PassengerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _loading = false;

  bool get _enabled => expressPassengerAdsEnabled(
        settings: widget.settings,
        previewMode: ExpressRuntimeChannel.previewMode,
        placement: widget.placement,
      );

  AdSize get _size => widget.placement == PassengerAdPlacement.activeTrip
      ? AdSize.mediumRectangle
      : AdSize.banner;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant PassengerAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings ||
        oldWidget.placement != widget.placement) {
      if (!_enabled) {
        _disposeAd();
      } else {
        _maybeLoad();
      }
    }
  }

  Future<void> _maybeLoad() async {
    final adUnitId = ExpressPassengerAds.bannerUnitId(widget.settings);
    if (!_enabled || adUnitId.isEmpty || _loading || _ad != null) {
      return;
    }

    _loading = true;
    try {
      await ExpressPassengerAds.initialize();
      if (!mounted || !_enabled) return;

      final ad = BannerAd(
        adUnitId: adUnitId,
        size: _size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (loadedAd) {
            if (!mounted || loadedAd != _ad) return;
            setState(() => _loaded = true);
          },
          onAdFailedToLoad: (failedAd, error) {
            failedAd.dispose();
            if (!mounted) return;
            setState(() {
              _ad = null;
              _loaded = false;
            });
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      _disposeAd();
    } finally {
      _loading = false;
    }
  }

  void _disposeAd() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
  }

  @override
  void dispose() {
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_enabled || !_loaded || ad == null) {
      return const SizedBox.shrink();
    }

    final size = ad.size;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Publicidad',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .55),
                ),
          ),
          const SizedBox(height: 5),
          Center(
            child: SizedBox(
              width: size.width.toDouble(),
              height: size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        ],
      ),
    );
  }
}
).hasMatch(remote)) {
      return remote;
    }
    return _productionBannerUnitId.trim();
  }

  static bool get configured =>
      ExpressRuntimeChannel.previewMode || _productionBannerUnitId.trim().isNotEmpty;

  static Future<void> initialize() {
    // Initialization is safe and idempotent; it is only used by active ad slots
    // for remote-configured Production banners, or Preview test banners.
    return _initialization ??= MobileAds.instance.initialize().then((_) {});
  }
}

class PassengerAdSlot extends StatefulWidget {
  final Map<String, dynamic> settings;
  final PassengerAdPlacement placement;

  const PassengerAdSlot({
    super.key,
    required this.settings,
    required this.placement,
  });

  @override
  State<PassengerAdSlot> createState() => _PassengerAdSlotState();
}

class _PassengerAdSlotState extends State<PassengerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _loading = false;

  bool get _enabled => expressPassengerAdsEnabled(
        settings: widget.settings,
        previewMode: ExpressRuntimeChannel.previewMode,
        placement: widget.placement,
      );

  AdSize get _size => widget.placement == PassengerAdPlacement.activeTrip
      ? AdSize.mediumRectangle
      : AdSize.banner;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant PassengerAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings ||
        oldWidget.placement != widget.placement) {
      if (!_enabled) {
        _disposeAd();
      } else {
        _maybeLoad();
      }
    }
  }

  Future<void> _maybeLoad() async {
    if (!_enabled ||
        !ExpressPassengerAds.configured ||
        _loading ||
        _ad != null) {
      return;
    }

    _loading = true;
    try {
      await ExpressPassengerAds.initialize();
      if (!mounted || !_enabled) return;

      final ad = BannerAd(
        adUnitId: ExpressPassengerAds.bannerUnitId,
        size: _size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (loadedAd) {
            if (!mounted || loadedAd != _ad) return;
            setState(() => _loaded = true);
          },
          onAdFailedToLoad: (failedAd, error) {
            failedAd.dispose();
            if (!mounted) return;
            setState(() {
              _ad = null;
              _loaded = false;
            });
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      _disposeAd();
    } finally {
      _loading = false;
    }
  }

  void _disposeAd() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
  }

  @override
  void dispose() {
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_enabled || !_loaded || ad == null) {
      return const SizedBox.shrink();
    }

    final size = ad.size;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Publicidad',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .55),
                ),
          ),
          const SizedBox(height: 5),
          Center(
            child: SizedBox(
              width: size.width.toDouble(),
              height: size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        ],
      ),
    );
  }
}

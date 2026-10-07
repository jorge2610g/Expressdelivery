import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/runtime_channel.dart';
import 'services/express_service.dart';

const String _googleTestBannerId =
    'ca-app-pub-3940256099942544/9214589741';
const String _compiledProductionBannerId = String.fromEnvironment(
  'EXPRESS_ADMOB_PASSENGER_BANNER_ID',
);

Future<void> initializeExpressAds() async {
  if (!Platform.isAndroid) return;
  await MobileAds.instance.initialize();
}

class ExpressPassengerAdBanner extends StatefulWidget {
  final ExpressService service;
  final String placement;

  const ExpressPassengerAdBanner({
    super.key,
    required this.service,
    required this.placement,
  });

  @override
  State<ExpressPassengerAdBanner> createState() =>
      _ExpressPassengerAdBannerState();
}

class _ExpressPassengerAdBannerState extends State<ExpressPassengerAdBanner> {
  BannerAd? _banner;
  bool _eligible = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  bool _validBannerId(String value) {
    final id = value.trim();
    return id.startsWith('ca-app-pub-') && id.contains('/');
  }

  Future<void> _prepare() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final settings = await widget.service.appSettings();
      final enabled = settings['ads_passenger_enabled'] == true;
      final placementEnabled = switch (widget.placement) {
        'home' => settings['ads_passenger_home_enabled'] != false,
        'trip' => settings['ads_passenger_trip_enabled'] != false,
        _ => false,
      };

      if (!enabled || !placementEnabled) {
        if (mounted) {
          setState(() {
            _eligible = false;
            _loading = false;
          });
        }
        return;
      }

      final remoteId =
          settings['admob_passenger_banner_unit_id']?.toString().trim() ?? '';
      final adUnitId = ExpressRuntimeChannel.previewMode
          ? _googleTestBannerId
          : (_validBannerId(remoteId)
              ? remoteId
              : _compiledProductionBannerId.trim());

      // Production remains visually clean until a real AdMob banner ID is
      // configured. Preview always uses Google's official test unit.
      if (!_validBannerId(adUnitId)) {
        if (mounted) {
          setState(() {
            _eligible = false;
            _loading = false;
          });
        }
        return;
      }

      final banner = BannerAd(
        adUnitId: adUnitId,
        request: const AdRequest(),
        size: AdSize.banner,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }
            setState(() {
              _eligible = true;
              _loading = false;
            });
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            if (mounted) {
              setState(() {
                _eligible = false;
                _loading = false;
              });
            }
          },
        ),
      );

      _banner = banner;
      await banner.load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _eligible = false;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (_loading || !_eligible || banner == null) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: 'Publicidad',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Publicidad',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            Center(
              child: SizedBox(
                width: banner.size.width.toDouble(),
                height: banner.size.height.toDouble(),
                child: AdWidget(ad: banner),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

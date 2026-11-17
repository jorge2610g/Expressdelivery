import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/supabase_client.dart';

/// Enlaces de redes sociales de Express (TikTok, Facebook, Instagram).
///
/// Los enlaces se editan desde Adminexpress. Se cargan una sola vez por sesión
/// con la RPC pública `app_social_links_public_v1`. Si la carga falla o un
/// enlace está vacío, no se muestra ese botón; si no hay ninguno, no se muestra
/// nada y el menú sigue igual.
class ExpressSocialLinksRow extends StatelessWidget {
  const ExpressSocialLinksRow({super.key, required this.audience});

  /// 'passenger' o 'driver'.
  final String audience;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Map<String, String>>>(
      future: _loadSocialLinks(),
      builder: (context, snapshot) {
        final links = snapshot.data?[audience] ?? const <String, String>{};
        final buttons = <Widget>[
          for (final network in _networks)
            if (links[network.key] != null)
              _SocialButton(network: network, url: links[network.key]!),
        ];
        if (buttons.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: buttons,
        );
      },
    );
  }
}

class _SocialNetwork {
  const _SocialNetwork({
    required this.key,
    required this.label,
    required this.asset,
  });

  final String key;
  final String label;
  final String asset;
}

const List<_SocialNetwork> _networks = [
  _SocialNetwork(
    key: 'tiktok',
    label: 'TikTok de Express',
    asset: 'assets/social/tiktok.png',
  ),
  _SocialNetwork(
    key: 'facebook',
    label: 'Facebook de Express',
    asset: 'assets/social/facebook.png',
  ),
  _SocialNetwork(
    key: 'instagram',
    label: 'Instagram de Express',
    asset: 'assets/social/instagram.png',
  ),
];

Future<Map<String, Map<String, String>>>? _sessionLinks;

/// Carga los enlaces una vez por sesión. Si falla, se borra la caché para
/// reintentar la próxima vez que se abra el menú.
Future<Map<String, Map<String, String>>> _loadSocialLinks() {
  return _sessionLinks ??= _fetchSocialLinks().then((links) {
    if (links == null) {
      _sessionLinks = null;
      return const <String, Map<String, String>>{};
    }
    return links;
  });
}

Future<Map<String, Map<String, String>>?> _fetchSocialLinks() async {
  try {
    final raw = await supabase
        .rpc('app_social_links_public_v1')
        .timeout(const Duration(seconds: 8));
    return _parseSocialLinks(raw);
  } catch (_) {
    return null;
  }
}

Map<String, Map<String, String>> _parseSocialLinks(dynamic raw) {
  final result = <String, Map<String, String>>{};
  if (raw is! Map) return result;
  for (final audience in const ['passenger', 'driver']) {
    final block = raw[audience];
    if (block is! Map) continue;
    final links = <String, String>{};
    block.forEach((key, value) {
      final url = value is String ? value.trim() : '';
      if (url.startsWith('https://')) {
        links[key.toString()] = url;
      }
    });
    result[audience] = links;
  }
  return result;
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.network, required this.url});

  final _SocialNetwork network;
  final String url;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: network.label,
      child: Tooltip(
        message: network.label,
        child: SizedBox(
          width: 40,
          height: 40,
          child: InkResponse(
            onTap: () => _open(context),
            radius: 20,
            customBorder: const CircleBorder(),
            child: Center(
              child: ClipOval(
                child: Image.asset(
                  network.asset,
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

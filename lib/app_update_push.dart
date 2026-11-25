import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Notificación «Nueva actualización»: al tocarla, si la versión instalada es anterior se abre Google Play;
/// si ya está actualizada, solo se abre la app (no se hace nada más).
const String expressPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.express.usuario1';

/// Build objetivo de un `deep_link` «app_update/<build>», o `null` si no lo es.
int? appUpdateTargetBuild(String? deepLink) {
  final parts = deepLink?.split('/') ?? const <String>[];
  if (parts.length != 2 || parts.first != 'app_update') return null;
  return int.tryParse(parts.last);
}

/// ¿Hay que llevar al usuario a la tienda? Solo si su build instalado es menor al publicado.
bool appUpdateNeedsStore(int installedBuild, int targetBuild) =>
    installedBuild > 0 && installedBuild < targetBuild;

/// Abre Google Play si el teléfono tiene una versión anterior. Devuelve `true` si abrió la tienda.
Future<bool> openStoreIfOutdated(String? deepLink) async {
  if (kIsWeb) return false;
  final target = appUpdateTargetBuild(deepLink);
  if (target == null) return false;
  final info = await PackageInfo.fromPlatform();
  final installed = int.tryParse(info.buildNumber) ?? 0;
  if (!appUpdateNeedsStore(installed, target)) return false;
  return launchUrl(
    Uri.parse(expressPlayStoreUrl),
    mode: LaunchMode.externalApplication,
  );
}

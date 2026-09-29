import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'platform_reload.dart';

class AppUpdateBanner extends StatefulWidget {
  final String currentPackageVersion;
  final String currentDisplayVersion;

  const AppUpdateBanner({
    super.key,
    required this.currentPackageVersion,
    required this.currentDisplayVersion,
  });

  @override
  State<AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends State<AppUpdateBanner> {
  Timer? _timer;
  String? _availableDisplayVersion;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _checkForUpdate();
      _timer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _checkForUpdate(),
      );
    }
  }

  Future<void> _checkForUpdate() async {
    if (!kIsWeb || _checking) return;
    _checking = true;

    try {
      final uri = Uri.base
          .resolve('version.json')
          .replace(
            queryParameters: {
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          );

      final response = await http.get(
        uri,
        headers: const {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
      );

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;

      final remote = Map<String, dynamic>.from(decoded);
      final packageVersion = remote['package']?.toString();
      final displayVersion = remote['display']?.toString();

      if (!mounted) return;

      if (packageVersion != null &&
          packageVersion.isNotEmpty &&
          packageVersion != widget.currentPackageVersion) {
        setState(() {
          _availableDisplayVersion =
              displayVersion?.isNotEmpty == true
                  ? displayVersion
                  : packageVersion;
        });
      } else if (_availableDisplayVersion != null) {
        setState(() => _availableDisplayVersion = null);
      }
    } catch (_) {
      // Si no hay conexión o version.json aún no existe, se vuelve a intentar
      // automáticamente en el siguiente ciclo.
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableDisplayVersion;
    if (available == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0B57D0),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.system_update_alt_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Actualización disponible',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          available,
                          style: const TextStyle(
                            color: Color(0xFFDCEAFF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: reloadExpressApp,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0B57D0),
                    ),
                    child: const Text('Actualizar ahora'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

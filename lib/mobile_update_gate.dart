import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/supabase_client.dart';

class AndroidReleaseUpdateGate extends StatefulWidget {
  final Widget child;

  const AndroidReleaseUpdateGate({
    super.key,
    required this.child,
  });

  @override
  State<AndroidReleaseUpdateGate> createState() =>
      _AndroidReleaseUpdateGateState();
}

class _AndroidReleaseUpdateGateState extends State<AndroidReleaseUpdateGate> {
  Timer? timer;
  Map<String, dynamic>? release;
  int currentBuild = 0;
  bool hidden = false;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    _check();
    timer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _check(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (checking) return;
    checking = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      final raw = await supabase.rpc(
        'latest_app_release',
        params: {'p_platform': 'android'},
      );

      Map<String, dynamic>? next;
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        final remote = (map['build_number'] as num?)?.toInt() ??
            int.tryParse(map['build_number']?.toString() ?? '') ??
            0;
        if (remote > build) next = map;
      }

      if (!mounted) return;
      setState(() {
        currentBuild = build;
        release = next;
        if (next == null) hidden = false;
      });
    } catch (_) {
      // La app sigue funcionando si no se puede consultar una actualización.
    } finally {
      checking = false;
    }
  }

  Future<void> _open(String? value) async {
    if (value == null || value.trim().isEmpty) return;
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final data = release;
    if (data == null || hidden) return widget.child;

    final mandatory = data['mandatory'] == true;
    final version = data['version_name']?.toString() ?? 'Nueva versión';
    final build = data['build_number']?.toString() ?? '';
    final notes = data['changelog']?.toString().trim() ?? '';
    final apk = data['apk_url']?.toString();
    final play = data['play_store_url']?.toString();

    final card = Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                CircleAvatar(
                  backgroundColor: Color(0xFF0B57D0),
                  child: Icon(
                    Icons.system_update_alt_rounded,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Actualización disponible',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Express v$version · build $build',
              style: const TextStyle(
                color: Color(0xFFDCEAFF),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                notes,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFD1D5DB),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Tu build actual es $currentBuild.',
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (apk?.isNotEmpty == true)
                  FilledButton.icon(
                    onPressed: () => _open(apk),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Descargar APK'),
                  ),
                if (play?.isNotEmpty == true)
                  OutlinedButton.icon(
                    onPressed: () => _open(play),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.shop_2_outlined),
                    label: const Text('Play Store'),
                  ),
                if (!mandatory)
                  TextButton(
                    onPressed: () => setState(() => hidden = true),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFD1D5DB),
                    ),
                    child: const Text('Más tarde'),
                  ),
              ],
            ),
            if (mandatory) ...[
              const SizedBox(height: 8),
              const Text(
                'Esta actualización es obligatoria para continuar.',
                style: TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (mandatory) {
      return Stack(
        children: [
          Positioned.fill(child: widget.child),
          const Positioned.fill(
            child: ModalBarrier(
              dismissible: false,
              color: Color(0x99000000),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(child: SingleChildScrollView(child: card)),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: card,
            ),
          ),
        ),
      ],
    );
  }
}

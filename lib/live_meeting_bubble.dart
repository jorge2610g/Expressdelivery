import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/express_service.dart';

/// «En directo»: círculo rojo parpadeante sobre la pantalla cuando la administración
/// activa una reunión de Google Meet. Al tocarlo se abre una hoja con el botón para entrar.
const Color _liveRed = Color(0xFFE5252A);

/// Minutos desde que empezó la reunión (para el texto «Empezó hace N min»).
int liveMeetingMinutesSince(Object? startedAt, DateTime now) {
  final start = DateTime.tryParse(startedAt?.toString() ?? '');
  if (start == null) return 0;
  final minutes = now.difference(start.toLocal()).inMinutes;
  return minutes < 0 ? 0 : minutes;
}

String liveMeetingStartedText(int minutes) {
  if (minutes < 1) return 'Acaba de empezar';
  if (minutes < 60) return 'Empezó hace $minutes min';
  final hours = minutes ~/ 60;
  return 'Empezó hace $hours h';
}

bool liveMeetingUrlAllowed(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && uri.host == 'meet.google.com';
}

class LiveMeetingOverlay extends StatefulWidget {
  final ExpressService service;
  final Widget child;

  const LiveMeetingOverlay({
    super.key,
    required this.service,
    required this.child,
  });

  @override
  State<LiveMeetingOverlay> createState() => _LiveMeetingOverlayState();
}

class _LiveMeetingOverlayState extends State<LiveMeetingOverlay>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Map<String, dynamic>? meeting;
  Timer? timer;
  late final AnimationController pulse;

  @override
  void initState() {
    super.initState();
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    pulse.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final next = await widget.service.myLiveMeeting();
      if (!mounted) return;
      if (next?['id'] != meeting?['id'] ||
          (next == null) != (meeting == null)) {
        setState(() => meeting = next);
      }
    } catch (_) {
      // Sin red o sin sesión: se conserva lo último que se mostró.
    }
  }

  Future<void> _open() async {
    final m = meeting;
    if (m == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final minutes = liveMeetingMinutesSince(
          m['started_at'],
          DateTime.now(),
        );
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _liveRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: _liveRed),
                      SizedBox(width: 6),
                      Text(
                        'EN DIRECTO AHORA',
                        style: TextStyle(
                          color: _liveRed,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  m['title']?.toString() ?? 'Reunión en directo',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if ((m['message']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    m['message'].toString(),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _join(m);
                    },
                    icon: const Icon(Icons.videocam_rounded),
                    label: const Text('Unirme a la reunión'),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Ahora no'),
                  ),
                ),
                Center(
                  child: Text(
                    'Se abre Google Meet · ${liveMeetingStartedText(minutes)}',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _join(Map<String, dynamic> m) async {
    final url = m['meet_url']?.toString() ?? '';
    if (!liveMeetingUrlAllowed(url)) return;
    unawaited(
      widget.service
          .joinLiveMeeting(m['id'].toString())
          .catchError((Object _) {}),
    );
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir Google Meet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final top = MediaQuery.of(context).padding.top + 124;
    return Stack(
      children: [
        widget.child,
        if (meeting != null)
          Positioned(
            right: 14,
            top: top,
            child: Material(
              type: MaterialType.transparency,
              child: Semantics(
                button: true,
                label: 'Estamos en directo. Toca para ver la reunión',
                child: GestureDetector(
                  onTap: _open,
                  child: SizedBox(
                    width: 74,
                    height: 74,
                    child: AnimatedBuilder(
                      animation: pulse,
                      builder: (context, _) {
                        final t = reduceMotion ? 0.0 : pulse.value;
                        double ring(double offset) {
                          final v = (t + offset) % 1.0;
                          return v;
                        }

                        Widget ringWidget(double v) => Opacity(
                          opacity: reduceMotion ? 0 : (1 - v) * 0.8,
                          child: Transform.scale(
                            scale: 1 + v * 0.7,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: _liveRed, width: 3),
                              ),
                            ),
                          ),
                        );
                        final blink = reduceMotion
                            ? 1.0
                            : (t < 0.5 ? 1.0 : 0.3);
                        return Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            ringWidget(ring(0)),
                            ringWidget(ring(0.5)),
                            Container(
                              width: 74,
                              height: 74,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: _liveRed,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x55000000),
                                    blurRadius: 14,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Opacity(
                                    opacity: blink,
                                    child: const Icon(
                                      Icons.circle,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'EN\nDIRECTO',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      height: 1.1,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

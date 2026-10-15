import 'package:flutter/material.dart';

import 'offline_status.dart';

/// Indicador discreto de conexión: arriba, sin velo y sin absorber toques.
/// Muestra la antigüedad de los últimos datos válidos. Nunca dice "en línea"
/// mientras la conexión no esté confirmada.
class ExpressOfflineBanner extends StatelessWidget {
  const ExpressOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final monitor = ExpressConnectivityMonitor.instance;
    return AnimatedBuilder(
      animation: monitor,
      builder: (context, _) {
        if (monitor.isOnline) return const SizedBox.shrink();
        final reconnecting =
            monitor.state == ExpressConnectionState.reconnecting;
        final saved = monitor.lastValidAt('passenger_home') ??
            monitor.lastValidAt('driver_home');
        final detail = saved == null
            ? 'sin datos guardados'
            : 'datos ${expressFreshnessLabel(saved, DateTime.now())}';
        final label = reconnecting
            ? 'Reconectando · $detail'
            : 'Sin conexión · $detail';
        return IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101828),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

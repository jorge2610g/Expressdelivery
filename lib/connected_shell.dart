import 'package:flutter/material.dart';

import 'connected_center.dart';
import 'connected_experience.dart';
import 'driver_setup.dart';
import 'services/express_service.dart';

class ConnectedAppShell extends StatefulWidget {
  final VoidCallback onExit;
  const ConnectedAppShell({super.key, required this.onExit});

  @override
  State<ConnectedAppShell> createState() => _ConnectedAppShellState();
}

class _ConnectedAppShellState extends State<ConnectedAppShell> {
  final service = ExpressService();
  int refresh = 0;

  Future<int> _unreadCount() async {
    final rows = await service.myNotifications();
    return rows.where((row) => row['is_read'] != true).length;
  }

  Future<void> _openCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExpressCenterPage(service: service)),
    );
    if (mounted) setState(() => refresh++);
  }

  Future<void> _openDriverSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DriverSetupPage(service: service)),
    );
    if (mounted) setState(() => refresh++);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: ConnectedExperience(onExit: widget.onExit)),
        Positioned(
          right: 16,
          bottom: 92,
          child: SafeArea(
            top: false,
            left: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'driver-setup',
                  tooltip: 'Perfil de conductor',
                  onPressed: _openDriverSetup,
                  child: const Icon(Icons.drive_eta_rounded),
                ),
                const SizedBox(height: 10),
                FutureBuilder<int>(
                  key: ValueKey(refresh),
                  future: _unreadCount(),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    return FloatingActionButton.small(
                      heroTag: 'express-center',
                      tooltip: 'Centro Express',
                      onPressed: _openCenter,
                      child: Badge(
                        isLabelVisible: count > 0,
                        label: Text(count > 99 ? '99+' : '$count'),
                        child: const Icon(Icons.notifications_active_outlined),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

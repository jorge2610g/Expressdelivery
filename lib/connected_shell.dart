import 'package:flutter/material.dart';

import 'admin_panel.dart';
import 'connected_center.dart';
import 'connected_experience.dart';
import 'driver_setup.dart';
import 'core/supabase_client.dart';
import 'services/express_service.dart';

class ConnectedAppShell extends StatefulWidget {
  final VoidCallback onExit;
  const ConnectedAppShell({super.key, required this.onExit});

  @override
  State<ConnectedAppShell> createState() => _ConnectedAppShellState();
}

class _ConnectedAppShellState extends State<ConnectedAppShell> {
  final service = ExpressService();
  late Future<bool> adminAccess;
  int refresh = 0;

  @override
  void initState() {
    super.initState();
    adminAccess = _isAdmin();
  }

  Future<bool> _isAdmin() async {
    try {
      return await supabase.rpc('is_admin') == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _account() => service.myUser();

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

  Future<void> _openAdmin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpressAdminPanel(
          onExit: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (mounted) setState(() => refresh++);
  }


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey('account-' + refresh.toString()),
      future: _account(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sync_problem_rounded, size: 52),
                        const SizedBox(height: 14),
                        const Text(
                          'No pudimos cargar tu perfil',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Tu sesión está abierta, pero la aplicación no pudo leer el perfil. Puedes reintentar sin cerrar sesión.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF667085),
                            height: 1.45,
                          ),
                        ),
                        if (snapshot.hasError) ...[
                          const SizedBox(height: 10),
                          Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF98A2B3),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => setState(() => refresh++),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Reintentar'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: widget.onExit,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Cerrar sesión'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final status = snapshot.data!['account_status']?.toString() ?? 'active';
        if (status != 'active') {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status == 'blocked'
                              ? Icons.block_rounded
                              : Icons.pause_circle_outline_rounded,
                          size: 56,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          status == 'blocked'
                              ? 'Cuenta bloqueada'
                              : 'Cuenta suspendida',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Tu cuenta no puede usar viajes, delivery, chat ni pagos en este momento. Contacta al administrador de Express.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF667085),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: widget.onExit,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Cerrar sesión'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: ConnectedExperience(onExit: widget.onExit),
            ),
            Positioned(
              right: 16,
              bottom: 92,
              child: SafeArea(
                top: false,
                left: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FutureBuilder<bool>(
                      future: adminAccess,
                      builder: (context, adminSnapshot) {
                        if (adminSnapshot.data != true) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FloatingActionButton.small(
                            heroTag: 'express-admin',
                            tooltip: 'Panel administrador',
                            onPressed: _openAdmin,
                            child: const Icon(
                              Icons.admin_panel_settings_rounded,
                            ),
                          ),
                        );
                      },
                    ),
                    FloatingActionButton.small(
                      heroTag: 'driver-setup',
                      tooltip: 'Perfil de conductor',
                      onPressed: _openDriverSetup,
                      child: const Icon(Icons.drive_eta_rounded),
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: supabase
                          .from('notifications')
                          .stream(primaryKey: ['id'])
                          .eq('user_id', service.userId),
                      builder: (context, snapshot) {
                        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                        final count = rows.where((row) => row['is_read'] != true).length;
                        return FloatingActionButton.small(
                          heroTag: 'express-center',
                          tooltip: 'Centro Express',
                          onPressed: _openCenter,
                          child: Badge(
                            isLabelVisible: count > 0,
                            label: Text(count > 99 ? '99+' : count.toString()),
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
      },
    );
  }
}

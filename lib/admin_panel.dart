import 'package:flutter/material.dart';
import 'core/supabase_client.dart';

class ExpressAdminPanel extends StatefulWidget {
  final VoidCallback onExit;
  const ExpressAdminPanel({super.key, required this.onExit});

  @override
  State<ExpressAdminPanel> createState() => _ExpressAdminPanelState();
}

class _ExpressAdminPanelState extends State<ExpressAdminPanel> {
  int section = 0;
  int revision = 0;

  Future<bool> _authorized() async => await supabase.rpc('is_admin') == true;

  Future<Map<String, dynamic>> _stats() async {
    final value = await supabase.rpc('admin_stats');
    return Map<String, dynamic>.from(value as Map);
  }

  Future<List<Map<String, dynamic>>> _drivers() async {
    final value = await supabase.rpc('admin_driver_queue');
    return List<Map<String, dynamic>>.from(value as List);
  }

  Future<List<Map<String, dynamic>>> _users() async {
    final value = await supabase.rpc('admin_user_list');
    return List<Map<String, dynamic>>.from(value as List);
  }

  Future<void> _driverStatus(String id, String status) async {
    try {
      await supabase.rpc('admin_set_driver_approval',
          params: {'p_user_id': id, 'p_status': status});
      if (!mounted) return;
      setState(() => revision++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conductor: ' + status)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: ' + e.toString())));
    }
  }

  Future<void> _accountStatus(String id, String status) async {
    try {
      await supabase.rpc('admin_set_account_status',
          params: {'p_user_id': id, 'p_status': status});
      if (!mounted) return;
      setState(() => revision++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cuenta: ' + status)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: ' + e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _authorized(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data != true) {
          return Scaffold(
            body: Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 52),
                      const SizedBox(height: 12),
                      const Text('Acceso de administrador',
                          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      const Text(
                        'Esta cuenta no está autorizada. El registro público solo crea clientes y conductores.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
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
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          appBar: AppBar(
            title: const Text('Express Admin'),
            actions: [
              IconButton(
                onPressed: () => setState(() => revision++),
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                onPressed: widget.onExit,
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: section,
                onDestinationSelected: (v) => setState(() => section = v),
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard_rounded),
                    label: Text('Resumen'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.drive_eta_outlined),
                    selectedIcon: Icon(Icons.drive_eta_rounded),
                    label: Text('Conductores'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.people_outline_rounded),
                    selectedIcon: Icon(Icons.people_rounded),
                    label: Text('Usuarios'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(
                  index: section,
                  children: [
                    _dashboard(),
                    _driverList(),
                    _userList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dashboard() {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('stats-' + revision.toString()),
      future: _stats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _error(snapshot.error);
        final s = snapshot.data ?? {};
        final values = <(String, Object?, IconData)>[
          ('Usuarios', s['users'], Icons.people_rounded),
          ('Conductores', s['drivers'], Icons.drive_eta_rounded),
          ('Pendientes', s['drivers_pending'], Icons.hourglass_top_rounded),
          ('Aprobados', s['drivers_approved'], Icons.verified_rounded),
          ('Solicitudes de viaje', s['ride_requests'], Icons.local_taxi_rounded),
          ('Viajes activos', s['active_trips'], Icons.route_rounded),
          ('Viajes completados', s['completed_trips'], Icons.check_circle_outline_rounded),
          ('Delivery', s['deliveries'], Icons.local_shipping_rounded),
          ('Delivery activos', s['active_deliveries'], Icons.delivery_dining_rounded),
          ('Delivery completados', s['completed_deliveries'], Icons.inventory_2_outlined),
        ];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Resumen de la plataforma',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: values
                  .map((v) => SizedBox(
                        width: 230,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                CircleAvatar(child: Icon(v.$3)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text((v.$2 ?? 0).toString(),
                                          style: const TextStyle(
                                              fontSize: 25,
                                              fontWeight: FontWeight.w900)),
                                      Text(v.$1,
                                          style: const TextStyle(
                                              color: Color(0xFF667085))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _driverList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('drivers-' + revision.toString()),
      future: _drivers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _error(snapshot.error);
        final rows = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Conductores',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('Todavía no hay conductores registrados.'),
                ),
              ),
            ...rows.map((row) {
              final status = row['approval_status']?.toString() ?? 'pending';
              final name = row['full_name']?.toString().trim();
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(child: Icon(Icons.person_rounded)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name != null && name.isNotEmpty
                                      ? name
                                      : 'Conductor',
                                  style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w900),
                                ),
                                Text(row['email']?.toString() ?? ''),
                              ],
                            ),
                          ),
                          Chip(label: Text(status)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Teléfono: ' + (row['phone']?.toString() ?? '—')),
                      Text('Licencia: ' + (row['license_number']?.toString() ?? '—')),
                      Text('Vehículo: ' + (row['vehicle_summary']?.toString() ?? '—')),
                      Text('Ciudad: ' + (row['city']?.toString() ?? '—')),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: status == 'approved'
                                ? null
                                : () => _driverStatus(
                                    row['user_id'].toString(), 'approved'),
                            child: const Text('Aprobar'),
                          ),
                          OutlinedButton(
                            onPressed: status == 'rejected'
                                ? null
                                : () => _driverStatus(
                                    row['user_id'].toString(), 'rejected'),
                            child: const Text('Rechazar'),
                          ),
                          OutlinedButton(
                            onPressed: status == 'suspended'
                                ? null
                                : () => _driverStatus(
                                    row['user_id'].toString(), 'suspended'),
                            child: const Text('Suspender'),
                          ),
                          TextButton(
                            onPressed: status == 'pending'
                                ? null
                                : () => _driverStatus(
                                    row['user_id'].toString(), 'pending'),
                            child: const Text('Pendiente'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _userList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('users-' + revision.toString()),
      future: _users(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _error(snapshot.error);
        final rows = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Usuarios',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('Todavía no hay usuarios registrados.'),
                ),
              ),
            ...rows.map((row) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(row['active_mode'] == 'driver'
                        ? Icons.drive_eta_rounded
                        : Icons.person_rounded),
                    title: Text(
                      row['full_name']?.toString().trim().isNotEmpty == true
                          ? row['full_name'].toString()
                          : row['email']?.toString() ?? 'Usuario',
                    ),
                    subtitle: Text(
                      (row['email']?.toString() ?? '') +
                          ' · ' +
                          (row['active_mode']?.toString() ?? 'passenger') +
                          ' · ' +
                          (row['account_status']?.toString() ?? 'active'),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) =>
                          _accountStatus(row['user_id'].toString(), v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'active', child: Text('Activar')),
                        PopupMenuItem(
                            value: 'suspended', child: Text('Suspender')),
                        PopupMenuItem(
                            value: 'blocked', child: Text('Bloquear')),
                      ],
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }

  Widget _error(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('No se pudo cargar: ' + error.toString()),
      ),
    );
  }
}

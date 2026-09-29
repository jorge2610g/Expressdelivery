import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'core/supabase_client.dart';

const Color adminBlue = Color(0xFF0B57D0);
const Color adminDark = Color(0xFF101828);
const Color adminMuted = Color(0xFF667085);
const Color adminBg = Color(0xFFF5F7FB);

class ExpressAdminPanel extends StatefulWidget {
  final VoidCallback onExit;
  const ExpressAdminPanel({super.key, required this.onExit});

  @override
  State<ExpressAdminPanel> createState() => _ExpressAdminPanelState();
}

class _ExpressAdminPanelState extends State<ExpressAdminPanel> {
  int section = 0;
  int revision = 0;

  static const sections = <(String, IconData)>[
    ('Dashboard', Icons.dashboard_rounded),
    ('Operación en vivo', Icons.map_rounded),
    ('Viajes', Icons.local_taxi_rounded),
    ('Delivery', Icons.local_shipping_rounded),
    ('Conductores', Icons.drive_eta_rounded),
    ('Usuarios', Icons.people_rounded),
    ('Seguridad / SOS', Icons.shield_rounded),
    ('Zonas', Icons.hexagon_outlined),
    ('Tarifas', Icons.payments_outlined),
    ('Pagos / Billetera', Icons.account_balance_wallet_rounded),
    ('Reportes', Icons.bar_chart_rounded),
    ('Configuración', Icons.settings_rounded),
    ('Builds', Icons.build_circle_outlined),
  ];

  Future<bool> _authorized() async => await supabase.rpc('is_admin') == true;

  Future<Map<String, dynamic>> _dashboardState() async {
    final value = await supabase.rpc('admin_dashboard_state');
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

  Future<List<Map<String, dynamic>>> _trips() async {
    final value = await supabase.rpc(
      'admin_trip_list',
      params: {'p_limit': 200},
    );
    return _list(value);
  }

  Future<List<Map<String, dynamic>>> _deliveries() async {
    final value = await supabase.rpc(
      'admin_delivery_list',
      params: {'p_limit': 200},
    );
    return _list(value);
  }

  void _refresh() => setState(() => revision++);

  Future<void> _driverStatus(String id, String status) async {
    try {
      await supabase.rpc(
        'admin_set_driver_approval',
        params: {'p_user_id': id, 'p_status': status},
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conductor: ' + status)),
      );
    } catch (e) {
      if (!mounted) return;
      _errorSnack(e);
    }
  }

  Future<void> _accountStatus(String id, String status) async {
    try {
      await supabase.rpc(
        'admin_set_account_status',
        params: {'p_user_id': id, 'p_status': status},
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cuenta: ' + status)),
      );
    } catch (e) {
      if (!mounted) return;
      _errorSnack(e);
    }
  }

  void _errorSnack(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: ' + error.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _authorized(),
      builder: (context, auth) {
        if (auth.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: adminBg,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (auth.data != true) {
          return _Unauthorized(onExit: widget.onExit);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;

            return Scaffold(
              backgroundColor: adminBg,
              appBar: compact
                  ? AppBar(
                      title: const _Brand(compact: true),
                      actions: [
                        IconButton(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        IconButton(
                          onPressed: widget.onExit,
                          icon: const Icon(Icons.logout_rounded),
                        ),
                      ],
                    )
                  : null,
              drawer: compact
                  ? Drawer(
                      child: SafeArea(
                        child: _Navigation(
                          selected: section,
                          onSelected: (value) {
                            Navigator.pop(context);
                            setState(() => section = value);
                          },
                          onExit: widget.onExit,
                        ),
                      ),
                    )
                  : null,
              body: Row(
                children: [
                  if (!compact)
                    SizedBox(
                      width: 248,
                      child: _Navigation(
                        selected: section,
                        onSelected: (value) =>
                            setState(() => section = value),
                        onExit: widget.onExit,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (!compact)
                          _TopBar(
                            title: sections[section].$1,
                            onRefresh: _refresh,
                            onExit: widget.onExit,
                          ),
                        Expanded(child: _body(section)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _body(int value) {
    switch (value) {
      case 0:
        return _dashboard();
      case 1:
        return _liveOperations();
      case 2:
        return _tripList();
      case 3:
        return _deliveryList();
      case 4:
        return _driverList();
      case 5:
        return _userList();
      case 6:
        return _security();
      case 7:
        return const _Coming(
          icon: Icons.hexagon_outlined,
          title: 'Zonas de operación',
          description:
              'Cobertura, radios, servicios permitidos y reglas por zona.',
        );
      case 8:
        return const _Coming(
          icon: Icons.payments_outlined,
          title: 'Motor de tarifas',
          description:
              'Tarifa base, km, minuto, mínimo, surge y comisiones.',
        );
      case 9:
        return const _Coming(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Pagos y Billetera',
          description:
              'Pagos, wallet, ganancias, retiros y conciliación.',
        );
      case 10:
        return const _Coming(
          icon: Icons.bar_chart_rounded,
          title: 'Reportes',
          description:
              'Reportes operativos y financieros con filtros y exportación.',
        );
      case 11:
        return const _Coming(
          icon: Icons.settings_rounded,
          title: 'Configuración',
          description:
              'Marca, módulos, vehículos, moneda y parámetros generales.',
        );
      case 12:
        return const _Coming(
          icon: Icons.build_circle_outlined,
          title: 'Build Center',
          description:
              'APK/AAB con GitHub Actions, historial y descargas.',
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _dashboard() {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('dashboard-' + revision.toString()),
      future: _dashboardState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading();
        }
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error, onRetry: _refresh);
        }

        final state = snapshot.data ?? const <String, dynamic>{};
        final metrics = _map(state['metrics']);
        final drivers = _list(state['drivers']);
        final trips = _list(state['active_trips']);
        final deliveries = _list(state['active_deliveries']);
        final emergencies = _list(state['emergencies']);
        final activity = _list(state['activity']);

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const _Header(
                title: 'Centro de operaciones',
                subtitle:
                    'Estado real de Viajes, Delivery, conductores, pagos y seguridad.',
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Metric(
                    'Conductores online',
                    metrics['drivers_online'],
                    Icons.online_prediction_rounded,
                  ),
                  _Metric(
                    'Buscando viaje',
                    metrics['ride_searching'],
                    Icons.radar_rounded,
                  ),
                  _Metric(
                    'Viajes activos',
                    metrics['active_trips'],
                    Icons.route_rounded,
                  ),
                  _Metric(
                    'Delivery activos',
                    metrics['active_deliveries'],
                    Icons.local_shipping_rounded,
                  ),
                  _Metric(
                    'Completados hoy',
                    metrics['completed_today'],
                    Icons.check_circle_rounded,
                  ),
                  _Metric(
                    'Cancelados hoy',
                    metrics['cancelled_today'],
                    Icons.cancel_outlined,
                  ),
                  _Metric(
                    'SOS abiertos',
                    metrics['open_emergencies'],
                    Icons.sos_rounded,
                    alert: (metrics['open_emergencies'] as num? ?? 0) > 0,
                  ),
                  _Metric(
                    'Cobrado hoy',
                    'Bs ' + (metrics['paid_volume_today'] ?? 0).toString(),
                    Icons.payments_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final map = _OperationsMap(
                    drivers: drivers,
                    trips: trips,
                    deliveries: deliveries,
                    emergencies: emergencies,
                  );
                  final recent = _Activity(rows: activity);

                  if (constraints.maxWidth < 1000) {
                    return Column(
                      children: [
                        SizedBox(height: 430, child: map),
                        const SizedBox(height: 14),
                        SizedBox(height: 430, child: recent),
                      ],
                    );
                  }

                  return SizedBox(
                    height: 470,
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: map),
                        const SizedBox(width: 14),
                        Expanded(flex: 2, child: recent),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              _Totals(metrics: metrics),
            ],
          ),
        );
      },
    );
  }

  Widget _liveOperations() {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('live-' + revision.toString()),
      future: _dashboardState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading();
        }
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error, onRetry: _refresh);
        }

        final state = snapshot.data ?? const <String, dynamic>{};

        return Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(
                title: 'Operación en vivo',
                subtitle:
                    'Conductores, viajes, delivery y alertas en el mapa.',
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _OperationsMap(
                  drivers: _list(state['drivers']),
                  trips: _list(state['active_trips']),
                  deliveries: _list(state['active_deliveries']),
                  emergencies: _list(state['emergencies']),
                  fullScreen: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tripList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('trips-' + revision.toString()),
      future: _trips(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading();
        }
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error, onRetry: _refresh);
        }

        final rows = snapshot.data ?? const [];
        return _Records(
          title: 'Viajes',
          subtitle: 'Historial y operación de viajes Express.',
          empty: 'Todavía no hay viajes.',
          rows: rows,
          item: (row) => _OperationCard(
            icon: Icons.local_taxi_rounded,
            title:
                (row['pickup_address'] ?? 'Origen').toString() +
                ' → ' +
                (row['destination_address'] ?? 'Destino').toString(),
            subtitle:
                (row['status'] ?? '—').toString() +
                ' · ' +
                (row['category'] ?? 'Express').toString() +
                ' · Bs ' +
                (row['final_fare'] ?? '—').toString(),
            details: [
              'Pasajero: ' + (row['passenger_name'] ?? '—').toString(),
              'Conductor: ' + (row['driver_name'] ?? '—').toString(),
              'Pago: ' + (row['payment_status'] ?? '—').toString(),
              'Creado: ' + _formatDate(row['created_at']),
            ],
          ),
        );
      },
    );
  }

  Widget _deliveryList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('delivery-' + revision.toString()),
      future: _deliveries(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading();
        }
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error, onRetry: _refresh);
        }

        final rows = snapshot.data ?? const [];
        return _Records(
          title: 'Delivery',
          subtitle: 'Pedidos y entregas de Express.',
          empty: 'Todavía no hay delivery.',
          rows: rows,
          item: (row) => _OperationCard(
            icon: Icons.local_shipping_rounded,
            title:
                (row['pickup_address'] ?? 'Origen').toString() +
                ' → ' +
                (row['dropoff_address'] ?? 'Destino').toString(),
            subtitle:
                (row['status'] ?? '—').toString() +
                ' · ' +
                (row['package_type'] ?? 'Paquete').toString() +
                ' · Bs ' +
                (row['proposed_fare'] ?? '—').toString(),
            details: [
              'Cliente: ' + (row['customer_name'] ?? '—').toString(),
              'Repartidor: ' + (row['courier_name'] ?? '—').toString(),
              'Pago: ' + (row['payment_method'] ?? '—').toString(),
              'Creado: ' + _formatDate(row['created_at']),
            ],
          ),
        );
      },
    );
  }

  Widget _driverList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('drivers-' + revision.toString()),
      future: _drivers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading();
        }
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error, onRetry: _refresh);
        }

        return _Records(
          title: 'Conductores',
          subtitle:
              'Aprobación, estado, licencia, vehículo y control de conductores.',
          empty: 'Todavía no hay conductores registrados.',
          rows: snapshot.data ?? const [],
          item: (row) {
            final status = (row['approval_status'] ?? 'pending').toString();
            final online = (row['online_status'] ?? 'offline').toString();
            final name = row['full_name']?.toString().trim();

            return Card(
              margin: const EdgeInsets.only(bottom: 11),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFFEAF2FF),
                          child: Icon(
                            online == 'online'
                                ? Icons.online_prediction_rounded
                                : Icons.person_rounded,
                            color: adminBlue,
                          ),
                        ),
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                row['email']?.toString() ?? '',
                                style: const TextStyle(color: adminMuted),
                              ),
                            ],
                          ),
                        ),
                        _Chip(status),
                        const SizedBox(width: 6),
                        _Chip(online),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Line(
                      Icons.phone_outlined,
                      row['phone']?.toString() ?? 'Sin teléfono',
                    ),
                    _Line(
                      Icons.badge_outlined,
                      'Licencia: ' +
                          (row['license_number']?.toString() ?? '—'),
                    ),
                    _Line(
                      Icons.directions_car_outlined,
                      'Vehículo: ' +
                          (row['vehicle_summary']?.toString() ?? '—'),
                    ),
                    _Line(
                      Icons.location_city_outlined,
                      'Ciudad: ' + (row['city']?.toString() ?? '—'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: status == 'approved'
                              ? null
                              : () => _driverStatus(
                                    row['user_id'].toString(),
                                    'approved',
                                  ),
                          child: const Text('Aprobar'),
                        ),
                        OutlinedButton(
                          onPressed: status == 'rejected'
                              ? null
                              : () => _driverStatus(
                                    row['user_id'].toString(),
                                    'rejected',
                                  ),
                          child: const Text('Rechazar'),
                        ),
                        OutlinedButton(
                          onPressed: status == 'suspended'
                              ? null
                              : () => _driverStatus(
                                    row['user_id'].toString(),
                                    'suspended',
                                  ),
                          child: const Text('Suspender'),
                        ),
                        TextButton(
                          onPressed: status == 'pending'
                              ? null
                              : () => _driverStatus(
                                    row['user_id'].toString(),
                                    'pending',
                                  ),
                          child: const Text('Pendiente'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _userList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('users-' + revision.toString()),
      future: _users(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading();
        }
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error, onRetry: _refresh);
        }

        return _Records(
          title: 'Usuarios',
          subtitle:
              'Pasajeros, conductores y control del estado de las cuentas.',
          empty: 'Todavía no hay usuarios registrados.',
          rows: snapshot.data ?? const [],
          item: (row) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  row['active_mode'] == 'driver'
                      ? Icons.drive_eta_rounded
                      : Icons.person_rounded,
                ),
              ),
              title: Text(
                row['full_name']?.toString().trim().isNotEmpty == true
                    ? row['full_name'].toString()
                    : row['email']?.toString() ?? 'Usuario',
              ),
              subtitle: Text(
                (row['email'] ?? '').toString() +
                    ' · ' +
                    (row['active_mode'] ?? 'passenger').toString() +
                    ' · ' +
                    (row['account_status'] ?? 'active').toString(),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _accountStatus(
                  row['user_id'].toString(),
                  value,
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'active',
                    child: Text('Activar'),
                  ),
                  PopupMenuItem(
                    value: 'suspended',
                    child: Text('Suspender'),
                  ),
                  PopupMenuItem(
                    value: 'blocked',
                    child: Text('Bloquear'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _security() {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('security-' + revision.toString()),
      future: _dashboardState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading();
        }
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error, onRetry: _refresh);
        }

        final rows = _list(snapshot.data?['emergencies']);
        return _Records(
          title: 'Seguridad / SOS',
          subtitle:
              'Emergencias activas registradas desde Viajes y Delivery.',
          empty: 'No hay emergencias abiertas.',
          rows: rows,
          item: (row) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFE4E8),
                child: Icon(Icons.sos_rounded, color: Color(0xFFD92D20)),
              ),
              title: Text(
                row['user_name']?.toString().trim().isNotEmpty == true
                    ? row['user_name'].toString()
                    : 'Usuario Express',
              ),
              subtitle: Text(
                (row['status'] ?? 'open').toString() +
                    ' · ' +
                    _formatDate(row['created_at']),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Navigation extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onExit;

  const _Navigation({
    required this.selected,
    required this.onSelected,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0B1739),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 24, 18, 18),
            child: _Brand(),
          ),
          const Divider(color: Color(0x22FFFFFF), height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: _ExpressAdminPanelState.sections.length,
              itemBuilder: (context, index) {
                final item = _ExpressAdminPanelState.sections[index];
                final active = index == selected;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: ListTile(
                    dense: true,
                    selected: active,
                    selectedTileColor: const Color(0xFF173B78),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(
                      item.$2,
                      color: active
                          ? Colors.white
                          : const Color(0xFFBFD1EA),
                    ),
                    title: Text(
                      item.$1,
                      style: TextStyle(
                        color: active
                            ? Colors.white
                            : const Color(0xFFD7E3F4),
                        fontWeight:
                            active ? FontWeight.w900 : FontWeight.w600,
                      ),
                    ),
                    onTap: () => onSelected(index),
                  ),
                );
              },
            ),
          ),
          const Divider(color: Color(0x22FFFFFF), height: 1),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.white70),
            title: const Text(
              'Cerrar sesión',
              style: TextStyle(color: Colors.white70),
            ),
            onTap: onExit,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final bool compact;
  const _Brand({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: adminBlue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EXPRESS',
              style: TextStyle(
                color: compact ? adminDark : Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'ADMIN',
              style: TextStyle(
                color: compact ? adminMuted : const Color(0xFFAEC5E7),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onRefresh;
  final VoidCallback onExit;

  const _TopBar({
    required this.title,
    required this.onRefresh,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E7EC))),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: onExit,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Header({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w900,
            color: adminDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: adminMuted, height: 1.35),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String title;
  final Object? value;
  final IconData icon;
  final bool alert;

  const _Metric(
    this.title,
    this.value,
    this.icon, {
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 218,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    alert ? const Color(0xFFFFE4E8) : const Color(0xFFEAF2FF),
                child: Icon(
                  icon,
                  color: alert ? const Color(0xFFD92D20) : adminBlue,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (value ?? 0).toString(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        color: adminMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationsMap extends StatelessWidget {
  final List<Map<String, dynamic>> drivers;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> emergencies;
  final bool fullScreen;

  const _OperationsMap({
    required this.drivers,
    required this.trips,
    required this.deliveries,
    required this.emergencies,
    this.fullScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];

    void addMarker(
      Map<String, dynamic> row,
      String latKey,
      String lngKey,
      IconData icon,
      String tooltip, {
      bool dark = false,
      bool alert = false,
      bool active = true,
    }) {
      final lat = _toDouble(row[latKey]);
      final lng = _toDouble(row[lngKey]);
      if (lat == null || lng == null) return;
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 46,
          height: 46,
          child: Tooltip(
            message: tooltip,
            child: _MapDot(
              icon: icon,
              dark: dark,
              alert: alert,
              active: active,
            ),
          ),
        ),
      );
    }

    for (final row in drivers) {
      final online = row['online_status'] == 'online';
      addMarker(
        row,
        'latitude',
        'longitude',
        Icons.drive_eta_rounded,
        (row['name'] ?? 'Conductor').toString() +
            ' · ' +
            (online ? 'Online' : 'Offline'),
        active: online,
      );
    }

    for (final row in trips) {
      addMarker(
        row,
        'pickup_latitude',
        'pickup_longitude',
        Icons.local_taxi_rounded,
        'Viaje · ' + (row['pickup_address'] ?? 'Origen').toString(),
        dark: true,
      );
    }

    for (final row in deliveries) {
      addMarker(
        row,
        'pickup_latitude',
        'pickup_longitude',
        Icons.local_shipping_rounded,
        'Delivery · ' + (row['pickup_address'] ?? 'Origen').toString(),
        dark: true,
      );
    }

    for (final row in emergencies) {
      addMarker(
        row,
        'latitude',
        'longitude',
        Icons.sos_rounded,
        'SOS · ' + (row['user_name'] ?? 'Usuario').toString(),
        alert: true,
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.map_outlined, color: adminBlue),
                SizedBox(width: 8),
                Text(
                  'Mapa operativo',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _center(
                  drivers,
                  trips,
                  deliveries,
                  emergencies,
                ),
                initialZoom: fullScreen ? 13 : 12,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.express.delivery',
                ),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapDot extends StatelessWidget {
  final IconData icon;
  final bool dark;
  final bool alert;
  final bool active;

  const _MapDot({
    required this.icon,
    this.dark = false,
    this.alert = false,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    final background = alert
        ? const Color(0xFFD92D20)
        : dark
            ? adminDark
            : active
                ? const Color(0xFF12B76A)
                : const Color(0xFF98A2B3);

    return Container(
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

class _Activity extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _Activity({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Actividad reciente',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'Todavía no hay actividad.',
                        style: TextStyle(color: adminMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _activityIcon(row['kind']?.toString()),
                            color: row['kind'] == 'emergency'
                                ? const Color(0xFFD92D20)
                                : adminBlue,
                          ),
                          title: Text(
                            row['title']?.toString() ?? 'Actividad',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            row['subtitle']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _formatTime(row['created_at']),
                            style: const TextStyle(
                              color: adminMuted,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  final Map<String, dynamic> metrics;
  const _Totals({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final items = <(String, Object?)>[
      ('Usuarios', metrics['users_total']),
      ('Conductores', metrics['drivers_total']),
      ('Pendientes', metrics['drivers_pending']),
      ('Viajes hoy', metrics['trips_today']),
      ('Delivery hoy', metrics['deliveries_today']),
      ('Delivery completados', metrics['completed_deliveries_today']),
    ];

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 34,
          runSpacing: 18,
          children: items
              .map(
                (item) => SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item.$2 ?? 0).toString(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        item.$1,
                        style: const TextStyle(
                          color: adminMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _Records extends StatelessWidget {
  final String title;
  final String subtitle;
  final String empty;
  final List<Map<String, dynamic>> rows;
  final Widget Function(Map<String, dynamic>) item;

  const _Records({
    required this.title,
    required this.subtitle,
    required this.empty,
    required this.rows,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _Header(title: title, subtitle: subtitle),
        const SizedBox(height: 18),
        if (rows.isEmpty)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                empty,
                style: const TextStyle(color: adminMuted),
              ),
            ),
          )
        else
          ...rows.map(item),
      ],
    );
  }
}

class _OperationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> details;

  const _OperationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEAF2FF),
          child: Icon(icon, color: adminBlue),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: details
                  .map(
                    (value) => Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        value,
                        style: const TextStyle(color: adminMuted),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(text, style: const TextStyle(fontSize: 10)),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(icon, size: 17, color: adminMuted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: adminMuted,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Coming extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _Coming({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _Header(title: title, subtitle: description),
        const SizedBox(height: 22),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Icon(icon, size: 52, color: adminBlue),
                const SizedBox(height: 14),
                const Text(
                  'Módulo preparado',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ya está incluido en la navegación. El siguiente bloque conectará sus datos y configuración en Supabase.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: adminMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: const [
        _Header(
          title: 'Cargando operación',
          subtitle: 'Sincronizando datos administrativos con Express.',
        ),
        SizedBox(height: 18),
        LinearProgressIndicator(),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'No se pudo cargar el módulo',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: adminMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Unauthorized extends StatelessWidget {
  final VoidCallback onExit;
  const _Unauthorized({required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: adminBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 52),
                  const SizedBox(height: 12),
                  const Text(
                    'Acceso de administrador',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Esta cuenta no está autorizada para administrar Express.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onExit,
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
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

LatLng _center(
  List<Map<String, dynamic>> drivers,
  List<Map<String, dynamic>> trips,
  List<Map<String, dynamic>> deliveries,
  List<Map<String, dynamic>> emergencies,
) {
  for (final row in emergencies) {
    final lat = _toDouble(row['latitude']);
    final lng = _toDouble(row['longitude']);
    if (lat != null && lng != null) return LatLng(lat, lng);
  }
  for (final row in drivers) {
    final lat = _toDouble(row['latitude']);
    final lng = _toDouble(row['longitude']);
    if (lat != null && lng != null) return LatLng(lat, lng);
  }
  for (final row in trips) {
    final lat = _toDouble(row['pickup_latitude']);
    final lng = _toDouble(row['pickup_longitude']);
    if (lat != null && lng != null) return LatLng(lat, lng);
  }
  for (final row in deliveries) {
    final lat = _toDouble(row['pickup_latitude']);
    final lng = _toDouble(row['pickup_longitude']);
    if (lat != null && lng != null) return LatLng(lat, lng);
  }
  return const LatLng(-20.2208, -70.1431);
}

IconData _activityIcon(String? kind) {
  switch (kind) {
    case 'delivery':
      return Icons.local_shipping_rounded;
    case 'emergency':
      return Icons.sos_rounded;
    default:
      return Icons.local_taxi_rounded;
  }
}

String _formatDate(Object? raw) {
  final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (value == null) return '—';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return day +
      '/' +
      month +
      '/' +
      value.year.toString() +
      ' · ' +
      hour +
      ':' +
      minute;
}

String _formatTime(Object? raw) {
  final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (value == null) return '';
  return value.hour.toString().padLeft(2, '0') +
      ':' +
      value.minute.toString().padLeft(2, '0');
}

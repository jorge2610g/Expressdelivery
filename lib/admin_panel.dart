import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'core/supabase_client.dart';
import 'admin_control_sections.dart';

const Color adminBlue = Color(0xFF0B57D0);
const Color adminDark = Color(0xFF101828);
const Color adminMuted = Color(0xFF667085);
const Color adminBg = Color(0xFFF7F9FC);


ThemeData _expressAdminTheme(BuildContext context) {
  final base = Theme.of(context);
  final scheme = ColorScheme.fromSeed(
    seedColor: adminBlue,
    brightness: Brightness.light,
    surface: Colors.white,
  );

  OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color),
      );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: adminBg,
    canvasColor: Colors.white,
    dividerColor: const Color(0xFFEAECF0),
    cardColor: Colors.white,
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE7ECF3)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: adminDark,
      surfaceTintColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 60,
      titleTextStyle: TextStyle(
        color: adminDark,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      labelStyle: const TextStyle(
        color: adminMuted,
        fontSize: 11,
      ),
      hintStyle: const TextStyle(
        color: Color(0xFF98A2B3),
        fontSize: 11,
      ),
      border: inputBorder(const Color(0xFFD0D5DD)),
      enabledBorder: inputBorder(const Color(0xFFD0D5DD)),
      focusedBorder: inputBorder(adminBlue),
      errorBorder: inputBorder(const Color(0xFFD92D20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        side: const BorderSide(color: Color(0xFFD0D5DD)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
        foregroundColor: adminDark,
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        maximumSize: const Size(42, 42),
        padding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFEAF2FF),
      disabledColor: const Color(0xFFF2F4F7),
      side: const BorderSide(color: Color(0xFFE4E7EC)),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      labelStyle: const TextStyle(
        color: adminDark,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: const TextStyle(
        color: adminBlue,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titleTextStyle: const TextStyle(
        color: adminDark,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
      ),
      textStyle: const TextStyle(
        color: adminDark,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: adminDark,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );
}

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
    ('Despacho manual', Icons.alt_route_rounded),
    ('Auditoría', Icons.history_rounded),
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

  void _goTo(int value) => setState(() => section = value);

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
  Future<void> _resolveEmergency(String id) async {
    try {
      await supabase.rpc(
        'admin_resolve_emergency',
        params: {'p_emergency_id': id},
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergencia marcada como resuelta.')),
      );
    } catch (e) {
      if (!mounted) return;
      _errorSnack(e);
    }
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

        return Theme(
          data: _expressAdminTheme(context),
          child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1180;

            return Scaffold(
              backgroundColor: adminBg,
              appBar: compact
                  ? AppBar(
                      title: const _Brand(compact: true),
                      actions: [
                        IconButton(
                          tooltip: 'Nuevo viaje',
                          onPressed: () => _goTo(13),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                        IconButton(
                          tooltip: 'Actualizar',
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Cuenta',
                          onSelected: (value) {
                            if (value == 'logout') widget.onExit();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'logout',
                              child: Text('Cerrar sesión'),
                            ),
                          ],
                          icon: const Icon(Icons.more_vert_rounded),
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
                            onNewTrip: () => _goTo(13),
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
        ),
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
        return const AdminZonesPage();
      case 8:
        return const AdminFaresPage();
      case 9:
        return const AdminPaymentsPage();
      case 10:
        return const AdminReportsPage();
      case 11:
        return const AdminSettingsPage();
      case 12:
        return const AdminBuildsPage();
      case 13:
        return const AdminDispatchPage();
      case 14:
        return const AdminAuditPage();
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
                title: 'Express Delivery',
                subtitle:
                    'Bienvenido al panel de control de tu empresa.',
                badge: 'Activa',
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final cardWidth = width < 700
                      ? width
                      : width < 1100
                          ? (width - 12) / 2
                          : (width - 36) / 4;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _Metric(
                          'Viajes activos',
                          metrics['active_trips'],
                          Icons.route_rounded,
                          tone: _MetricTone.blue,
                          footnote: 'En operación ahora',
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _Metric(
                          'Viajes hoy',
                          metrics['trips_today'],
                          Icons.local_taxi_rounded,
                          tone: _MetricTone.green,
                          footnote: 'Solicitudes del día',
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _Metric(
                          'Conductores conectados',
                          metrics['drivers_online'],
                          Icons.drive_eta_rounded,
                          tone: _MetricTone.orange,
                          footnote:
                              'de ' + (metrics['drivers_total'] ?? 0).toString(),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _Metric(
                          'Completados',
                          metrics['completed_today'],
                          Icons.check_circle_rounded,
                          tone: _MetricTone.purple,
                          footnote: 'Finalizados hoy',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final quick = _QuickActions(
                    onLive: () => _goTo(1),
                    onDrivers: () => _goTo(4),
                    onDispatch: () => _goTo(13),
                  );
                  final system = _SystemStatus(metrics: metrics);
                  if (constraints.maxWidth < 900) {
                    return Column(
                      children: [
                        quick,
                        const SizedBox(height: 14),
                        system,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: quick),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: system),
                    ],
                  );
                },
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

            return Container(
              margin: const EdgeInsets.only(bottom: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE7ECF3)),
                borderRadius: BorderRadius.circular(11),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final identity = Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFEAF2FF),
                        child: Icon(
                          online == 'online'
                              ? Icons.online_prediction_rounded
                              : Icons.person_rounded,
                          size: 18,
                          color: adminBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name != null && name.isNotEmpty
                                  ? name
                                  : 'Conductor',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: adminDark,
                              ),
                            ),
                            Text(
                              row['email']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: adminMuted,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );

                  final actions = PopupMenuButton<String>(
                    tooltip: 'Acciones',
                    onSelected: (value) => _driverStatus(
                      row['user_id'].toString(),
                      value,
                    ),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'approved',
                        child: Text('Aprobar'),
                      ),
                      PopupMenuItem(
                        value: 'pending',
                        child: Text('Marcar pendiente'),
                      ),
                      PopupMenuItem(
                        value: 'rejected',
                        child: Text('Rechazar'),
                      ),
                      PopupMenuItem(
                        value: 'suspended',
                        child: Text('Suspender'),
                      ),
                    ],
                    icon: const Icon(Icons.more_horiz_rounded),
                  );

                  if (wide) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: 240, child: identity),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              row['vehicle_summary']?.toString() ?? 'Sin vehículo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: adminMuted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              row['city']?.toString() ?? '—',
                              style: const TextStyle(
                                color: adminMuted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          _Chip(status),
                          const SizedBox(width: 6),
                          _Chip(online),
                          const SizedBox(width: 4),
                          actions,
                        ],
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.all(13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        identity,
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _Chip(status),
                            _Chip(online),
                          ],
                        ),
                        const SizedBox(height: 9),
                        _Line(
                          Icons.directions_car_outlined,
                          row['vehicle_summary']?.toString() ?? 'Sin vehículo',
                        ),
                        _Line(
                          Icons.phone_outlined,
                          row['phone']?.toString() ?? 'Sin teléfono',
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: actions,
                        ),
                      ],
                    ),
                  );
                },
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
          item: (row) => Container(
            margin: const EdgeInsets.only(bottom: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE7ECF3)),
              borderRadius: BorderRadius.circular(11),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFEAF2FF),
                child: Icon(
                  row['active_mode'] == 'driver'
                      ? Icons.drive_eta_rounded
                      : Icons.person_rounded,
                  size: 18,
                  color: adminBlue,
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
              trailing: FilledButton.icon(
                onPressed: () =>
                    _resolveEmergency(row['id'].toString()),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Resolver'),
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

  static const groups = <(String, List<int>)>[
    ('GENERAL', [0]),
    ('OPERACIONES', [1, 2, 13, 3, 4, 5, 6]),
    ('FINANZAS', [9, 8]),
    ('ANÁLISIS', [10, 14]),
    ('CONFIGURACIÓN', [7, 11, 12]),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: _Brand(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE7ECF3)),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFFE8F1FF),
                      child: Icon(
                        Icons.apartment_rounded,
                        size: 17,
                        color: adminBlue,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EMPRESA ACTUAL',
                            style: TextStyle(
                              color: adminMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .8,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Express Delivery',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: adminDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.unfold_more_rounded, size: 16, color: adminMuted),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEF1F5)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                children: [
                  for (final group in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
                      child: Text(
                        group.$1,
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .9,
                        ),
                      ),
                    ),
                    for (final index in group.$2)
                      _NavEntry(
                        index: index,
                        selected: selected == index,
                        onSelected: onSelected,
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEF1F5)),
            Padding(
              padding: const EdgeInsets.all(8),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: const Icon(
                  Icons.logout_rounded,
                  size: 19,
                  color: adminMuted,
                ),
                title: const Text(
                  'Cerrar sesión',
                  style: TextStyle(
                    color: adminDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: onExit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavEntry extends StatelessWidget {
  final int index;
  final bool selected;
  final ValueChanged<int> onSelected;

  const _NavEntry({
    required this.index,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final item = _ExpressAdminPanelState.sections[index];
    final alert = index == 6;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        selected: selected,
        selectedTileColor: const Color(0xFFEAF2FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
        leading: Icon(
          item.$2,
          size: 18,
          color: selected ? adminBlue : const Color(0xFF667085),
        ),
        title: Text(
          item.$1,
          style: TextStyle(
            color: selected ? adminBlue : adminDark,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        trailing: alert
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8E8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'SOS',
                  style: TextStyle(
                    color: Color(0xFFD92D20),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            : null,
        onTap: () => onSelected(index),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final bool compact;
  const _Brand({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Express Delivery',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: adminDark,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
        if (!compact)
          const Text(
            'Panel administrativo',
            style: TextStyle(
              color: adminMuted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );

    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          width: compact ? 32 : 36,
          height: compact ? 32 : 36,
          decoration: BoxDecoration(
            color: adminBlue,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.bolt_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 9),
        if (compact)
          Flexible(child: text)
        else
          Expanded(child: text),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onRefresh;
  final VoidCallback onNewTrip;
  final VoidCallback onExit;

  const _TopBar({
    required this.title,
    required this.onRefresh,
    required this.onNewTrip,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: adminDark,
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onNewTrip,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Nuevo viaje'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Reportar un problema',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Módulo de feedback en preparación.'),
                ),
              );
            },
            icon: const Icon(Icons.bug_report_outlined, size: 20),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Notificaciones',
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded, size: 20),
              ),
              const Positioned(
                right: 7,
                top: 7,
                child: CircleAvatar(
                  radius: 4,
                  backgroundColor: Color(0xFFD92D20),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE4E7EC)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Text(
              'ES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: 'Cuenta',
            onSelected: (value) {
              if (value == 'logout') onExit();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
            ],
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFFEAF2FF),
                  child: Icon(Icons.person_rounded, color: adminBlue, size: 18),
                ),
                SizedBox(width: 7),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Administrador',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Express Delivery',
                      style: TextStyle(
                        fontSize: 9,
                        color: adminMuted,
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 3),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? badge;

  const _Header({
    required this.title,
    required this.subtitle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: adminDark,
              ),
            ),
            if (badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8EF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Color(0xFF14804A),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: adminMuted,
            height: 1.35,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

enum _MetricTone { blue, green, orange, purple }

class _Metric extends StatelessWidget {
  final String title;
  final Object? value;
  final IconData icon;
  final bool alert;
  final _MetricTone tone;
  final String? footnote;

  const _Metric(
    this.title,
    this.value,
    this.icon, {
    this.alert = false,
    this.tone = _MetricTone.blue,
    this.footnote,
  });

  Color get _soft {
    if (alert) return const Color(0xFFFFE8E8);
    switch (tone) {
      case _MetricTone.green:
        return const Color(0xFFE8F8EF);
      case _MetricTone.orange:
        return const Color(0xFFFFF3E7);
      case _MetricTone.purple:
        return const Color(0xFFF1EBFF);
      case _MetricTone.blue:
        return const Color(0xFFEAF2FF);
    }
  }

  Color get _accent {
    if (alert) return const Color(0xFFD92D20);
    switch (tone) {
      case _MetricTone.green:
        return const Color(0xFF14804A);
      case _MetricTone.orange:
        return const Color(0xFFC76B16);
      case _MetricTone.purple:
        return const Color(0xFF6941C6);
      case _MetricTone.blue:
        return adminBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE7ECF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: adminMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (value ?? 0).toString(),
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: adminDark,
                  ),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    footnote!,
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 9,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onLive;
  final VoidCallback onDrivers;
  final VoidCallback onDispatch;

  const _QuickActions({
    required this.onLive,
    required this.onDrivers,
    required this.onDispatch,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        'Ver viajes en vivo',
        'Supervisa la operación en el mapa',
        Icons.map_rounded,
        const Color(0xFFE8F1FF),
        adminBlue,
        onLive,
      ),
      (
        'Gestionar conductores',
        'Estados, aprobación y vehículos',
        Icons.drive_eta_rounded,
        const Color(0xFFE8F8EF),
        const Color(0xFF14804A),
        onDrivers,
      ),
      (
        'Despacho manual',
        'Asigna un conductor directamente',
        Icons.alt_route_rounded,
        const Color(0xFFFFF3E7),
        const Color(0xFFC76B16),
        onDispatch,
      ),
    ];

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Acciones rápidas',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: adminDark,
            ),
          ),
          const SizedBox(height: 12),
          for (final action in actions) ...[
            InkWell(
              onTap: action.$6,
              borderRadius: BorderRadius.circular(11),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: action.$4,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Icon(action.$3, color: action.$5, size: 20),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.$1,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            action.$2,
                            style: const TextStyle(
                              color: adminMuted,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: adminMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (action != actions.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SystemStatus extends StatelessWidget {
  final Map<String, dynamic> metrics;

  const _SystemStatus({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Conductores', metrics['drivers_total'], Icons.drive_eta_rounded),
      ('Usuarios', metrics['users_total'], Icons.people_alt_outlined),
      ('Solicitudes', metrics['ride_searching'], Icons.radar_rounded),
      ('SOS', metrics['open_emergencies'], Icons.sos_rounded),
    ];
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estado del sistema',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: adminDark,
            ),
          ),
          const SizedBox(height: 9),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(row.$3, size: 17, color: adminMuted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    (row.$2 ?? 0).toString(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF12B76A),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  final Widget child;
  const _Surface({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE7ECF3)),
      ),
      child: child,
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
      surfaceTintColor: Colors.white,
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
      surfaceTintColor: Colors.white,
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
      surfaceTintColor: Colors.white,
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

class _Records extends StatefulWidget {
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
  State<_Records> createState() => _RecordsState();
}

class _RecordsState extends State<_Records> {
  final search = TextEditingController();
  String query = '';
  String? status;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = widget.rows
        .map((row) => row['status']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final visible = widget.rows.where((row) {
      final matchesText = query.isEmpty ||
          row.values
              .map((value) => value?.toString().toLowerCase() ?? '')
              .join(' ')
              .contains(query.toLowerCase());
      final matchesStatus =
          status == null || row['status']?.toString() == status;
      return matchesText && matchesStatus;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _Header(title: widget.title, subtitle: widget.subtitle),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE7ECF3)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: search,
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText: 'Buscar',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              ChoiceChip(
                label: Text('Todos (' + widget.rows.length.toString() + ')'),
                selected: status == null,
                onSelected: (_) => setState(() => status = null),
              ),
              for (final value in statuses.take(5))
                ChoiceChip(
                  label: Text(value),
                  selected: status == value,
                  onSelected: (_) => setState(() => status = value),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Exportación CSV/Excel se conectará en el módulo de reportes.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.download_rounded, size: 17),
                label: const Text('Exportar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7ECF3)),
            ),
            child: Text(
              query.isNotEmpty || status != null
                  ? 'No hay resultados para los filtros seleccionados.'
                  : widget.empty,
              style: const TextStyle(color: adminMuted),
            ),
          )
        else
          ...visible.map(widget.item),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7ECF3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(50, 0, 14, 12),
        leading: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: adminBlue, size: 17),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: adminMuted,
            fontSize: 10,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              children: details
                  .map(
                    (value) => Text(
                      value,
                      style: const TextStyle(
                        color: adminMuted,
                        fontSize: 10,
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
    final value = text.toLowerCase();
    final positive =
        value == 'approved' || value == 'online' || value == 'active';
    final warning = value == 'pending';
    final bg = positive
        ? const Color(0xFFE8F8EF)
        : warning
            ? const Color(0xFFFFF3E7)
            : const Color(0xFFF2F4F7);
    final fg = positive
        ? const Color(0xFF14804A)
        : warning
            ? const Color(0xFFC76B16)
            : const Color(0xFF475467);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
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

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'connected_center.dart';
import 'core/runtime_channel.dart';
import 'driver_setup.dart';
import 'driver_kyc_correction_page.dart';
import 'driver_priority_page.dart';
import 'driver_subscription_page.dart';
import 'money_format.dart';
import 'map_provider.dart';
import 'phone_verification_page.dart';
import 'services/express_service.dart';

const Color _hubBlue = Color(0xFF0B57D0);
const Color _hubDark = Color(0xFF101828);
const Color _hubMuted = Color(0xFF667085);
const Color _hubBg = Color(0xFFF6F7F9);

bool _hubDarkMode(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _hubBackground(BuildContext context) =>
    _hubDarkMode(context) ? const Color(0xFF0F1115) : _hubBg;

Color _hubSurface(BuildContext context) =>
    _hubDarkMode(context) ? const Color(0xFF17191D) : Colors.white;

Color _hubSoftSurface(BuildContext context) =>
    _hubDarkMode(context)
        ? const Color(0xFF22252B)
        : const Color(0xFFF5F7FA);

Color _hubText(BuildContext context) =>
    _hubDarkMode(context) ? const Color(0xFFF5F7FA) : _hubDark;

Color _hubMutedText(BuildContext context) =>
    _hubDarkMode(context) ? const Color(0xFFB3BBC8) : _hubMuted;

Color _hubBorder(BuildContext context) =>
    _hubDarkMode(context)
        ? const Color(0xFF343840)
        : const Color(0xFFE8EBF0);

double? _hubDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _hubRouteAddress(
  Map<String, dynamic> route, {
  required String addressKey,
  required String latitudeKey,
  required String longitudeKey,
  required String fallback,
}) {
  final text = route[addressKey]?.toString().trim() ?? '';
  final normalized = text.toLowerCase();
  final generic = text.isEmpty ||
      normalized == 'origen' ||
      normalized == 'destino' ||
      normalized == 'mi ubicación' ||
      normalized == 'mi ubicacion' ||
      normalized == 'mi ubicación actual' ||
      normalized == 'mi ubicacion actual' ||
      normalized == 'ubicación seleccionada' ||
      normalized == 'ubicacion seleccionada' ||
      normalized == 'punto seleccionado' ||
      normalized.contains('buscando dirección') ||
      normalized.contains('buscando direccion');
  if (!generic) return text;
  final lat = _hubDouble(route[latitudeKey]);
  final lng = _hubDouble(route[longitudeKey]);
  if (lat != null && lng != null) {
    return '$fallback · ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }
  return fallback;
}

String _hubMoney(Object? value, {Object? currency = 'BOB'}) =>
    expressMoney(value, currency);


String _hubDate(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (date == null) return '—';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return day + '/' + month + '/' + date.year.toString() + ' · ' + hour + ':' + minute;
}

String _hubPaymentLabel(Object? value) {
  switch (value?.toString()) {
    case 'wallet':
      return 'Billetera Express';
    case 'card':
      return 'Tarjeta';
    case 'driver_qr':
      return 'QR del conductor';
    case 'pagorut':
      return 'QR Bolivia';
    case 'mercado_pago':
      return 'Mercado Pago';
    case 'santander':
      return 'Banco Santander';
    case 'mach':
      return 'MACH';
    case 'tenpo':
      return 'Tenpo';
    default:
      return 'Efectivo';
  }
}

String _hubServiceLabel(Object? value) {
  switch (value?.toString()) {
    case 'comfort':
      return 'Comfort';
    case 'xl':
      return 'XL';
    case 'motorcycle':
      return 'Moto Express';
    default:
      return 'Viaje Express';
  }
}

String _hubStatusLabel(Object? value) {
  switch (value?.toString()) {
    case 'completed':
      return 'Completado';
    case 'cancelled':
      return 'Cancelado';
    case 'driver_assigned':
      return 'Conductor asignado';
    case 'driver_arriving':
      return 'Conductor en camino';
    case 'driver_waiting':
      return 'Conductor esperando';
    case 'in_progress':
      return 'En curso';
    case 'searching':
      return 'Buscando conductor';
    case 'offers_received':
      return 'Ofertas recibidas';
    default:
      return value?.toString() ?? 'Sin estado';
  }
}

Color _hubStatusColor(Object? value) {
  switch (value?.toString()) {
    case 'completed':
      return const Color(0xFF16A34A);
    case 'cancelled':
      return const Color(0xFFDC2626);
    case 'in_progress':
      return _hubBlue;
    default:
      return const Color(0xFF667085);
  }
}

class _HistoryEntry {
  final bool trip;
  final Map<String, dynamic> data;
  final Map<String, dynamic> route;
  final DateTime sortDate;

  const _HistoryEntry({
    required this.trip,
    required this.data,
    required this.route,
    required this.sortDate,
  });
}

class ExpressHistoryPage extends StatefulWidget {
  final ExpressService service;
  final bool driver;

  const ExpressHistoryPage({
    super.key,
    required this.service,
    required this.driver,
  });

  @override
  State<ExpressHistoryPage> createState() => _ExpressHistoryPageState();
}

class _ExpressHistoryPageState extends State<ExpressHistoryPage> {
  int refresh = 0;
  String filter = 'all';
  String period = 'today';
  late Future<List<_HistoryEntry>> historyFuture;

  @override
  void initState() {
    super.initState();
    historyFuture = _load();
  }

  ({DateTime from, DateTime to}) _periodRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (period) {
      'week' => today.subtract(Duration(days: today.weekday - DateTime.monday)),
      'month' => DateTime(now.year, now.month),
      _ => today,
    };
    return (from: from, to: now.add(const Duration(seconds: 1)));
  }

  void _reload({String? nextPeriod}) {
    setState(() {
      if (nextPeriod != null) period = nextPeriod;
      refresh++;
      historyFuture = _load();
    });
  }

  Future<List<_HistoryEntry>> _load() async {
    final range = _periodRange();
    final trips = await widget.service.myTrips(
      from: range.from,
      to: range.to,
      limit: 250,
    );
    final entries = <_HistoryEntry>[];

    for (final trip in trips) {
      final belongs = widget.driver
          ? trip['driver_id']?.toString() == widget.service.userId
          : trip['passenger_id']?.toString() == widget.service.userId;
      if (!belongs) continue;
      final status = trip['status']?.toString();
      if (status != 'completed' && status != 'cancelled') continue;
      final rawRoute = trip['ride_requests'];
      final route = rawRoute is Map
          ? Map<String, dynamic>.from(rawRoute)
          : <String, dynamic>{};
      final date = DateTime.tryParse(
            (trip['completed_at'] ?? trip['created_at'])?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      entries.add(
        _HistoryEntry(
          trip: true,
          data: Map<String, dynamic>.from(trip),
          route: route,
          sortDate: date,
        ),
      );
    }

    if (!widget.driver) {
      final rides = await widget.service.myRideRequests(
        from: range.from,
        to: range.to,
        limit: 250,
      );
      final linkedRideIds = trips
          .map((row) => row['ride_request_id']?.toString())
          .whereType<String>()
          .toSet();
      for (final ride in rides) {
        if (ride['status']?.toString() != 'cancelled') continue;
        if (linkedRideIds.contains(ride['id']?.toString())) continue;
        final date = DateTime.tryParse(ride['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        entries.add(
          _HistoryEntry(
            trip: false,
            data: Map<String, dynamic>.from(ride),
            route: Map<String, dynamic>.from(ride),
            sortDate: date,
          ),
        );
      }
    }

    entries.sort((a, b) => b.sortDate.compareTo(a.sortDate));
    return entries;
  }

  bool _visible(_HistoryEntry entry) {
    if (filter == 'all') return true;
    final status = entry.data['status']?.toString();
    if (filter == 'completed') return status == 'completed';
    if (filter == 'cancelled') return status == 'cancelled';
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hubBackground(context),
      appBar: AppBar(
        backgroundColor: _hubSurface(context),
        foregroundColor: _hubText(context),
        surfaceTintColor: _hubSurface(context),
        title: Text(
          widget.driver ? 'Historial de viajes' : 'Actividad',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<_HistoryEntry>>(
        key: ValueKey(refresh),
        future: historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _HubError(
              text: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final all = snapshot.data ?? const <_HistoryEntry>[];
          final rows = all.where(_visible).toList();
          final completed = all.where((e) => e.data['status'] == 'completed').length;
          final cancelled = all.where((e) => e.data['status'] == 'cancelled').length;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _HistoryFilter(
                        label: 'Hoy',
                        selected: period == 'today',
                        onTap: () => _reload(nextPeriod: 'today'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HistoryFilter(
                        label: 'Semana',
                        selected: period == 'week',
                        onTap: () => _reload(nextPeriod: 'week'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HistoryFilter(
                        label: 'Mes',
                        selected: period == 'month',
                        onTap: () => _reload(nextPeriod: 'month'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _HistoryFilter(
                        label: 'Todos (' + all.length.toString() + ')',
                        selected: filter == 'all',
                        onTap: () => setState(() => filter = 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HistoryFilter(
                        label: 'Completados (' + completed.toString() + ')',
                        selected: filter == 'completed',
                        onTap: () => setState(() => filter = 'completed'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HistoryFilter(
                        label: 'Cancelados (' + cancelled.toString() + ')',
                        selected: filter == 'cancelled',
                        onTap: () => setState(() => filter = 'cancelled'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  const _HubInfo(
                    icon: Icons.history_rounded,
                    title: 'Todavía no hay viajes aquí',
                    text: 'Los viajes completados y cancelados aparecerán en este historial.',
                  )
                else
                  ...rows.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _HistoryCard(
                        entry: entry,
                        driver: widget.driver,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExpressTripDetailPage(
                              service: widget.service,
                              entry: entry,
                              driver: widget.driver,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HistoryFilter extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HistoryFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 5),
        decoration: BoxDecoration(
          color: selected ? _hubSurface(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            bottom: BorderSide(
              color: selected ? _hubBlue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? _hubText(context) : _hubMutedText(context),
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final _HistoryEntry entry;
  final bool driver;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.entry,
    required this.driver,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = entry.data['status'];
    final route = entry.route;
    final fare = entry.trip
        ? entry.data['final_fare'] ?? route['proposed_fare']
        : route['proposed_fare'];
    final distance = _hubDouble(route['route_distance_km']);
    final duration = route['route_duration_minutes'];
    final payment = route['payment_method'];
    final currency = expressCurrencyCode(route['currency']);
    final statusColor = _hubStatusColor(status);

    return Material(
      color: _hubSurface(context),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _hubBorder(context)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _hubSoftSurface(context),
                    child: Icon(
                      driver ? Icons.person_rounded : Icons.local_taxi_rounded,
                      color: _hubText(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver ? 'Viaje con pasajero' : _hubServiceLabel(route['category']),
                          style: TextStyle(
                            color: _hubText(context),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _hubDate(entry.data['completed_at'] ?? entry.data['created_at']),
                          style: TextStyle(
                            color: _hubMutedText(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _hubStatusLabel(status),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _hubMutedText(context),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _RouteLine(
                icon: Icons.my_location_rounded,
                color: const Color(0xFF22A559),
                text: _hubRouteAddress(route, addressKey: 'pickup_address', latitudeKey: 'pickup_latitude', longitudeKey: 'pickup_longitude', fallback: 'Origen'),
              ),
              const SizedBox(height: 9),
              _RouteLine(
                icon: Icons.location_on_rounded,
                color: const Color(0xFFEF4444),
                text: _hubRouteAddress(route, addressKey: 'destination_address', latitudeKey: 'destination_latitude', longitudeKey: 'destination_longitude', fallback: 'Destino'),
              ),
              if (entry.trip && entry.data['status'] == 'completed') ...[
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _MiniHistoryMetric(
                        icon: Icons.payments_outlined,
                        text: _hubMoney(fare, currency: currency),
                      ),
                    ),
                    if (distance != null)
                      Expanded(
                        child: _MiniHistoryMetric(
                          icon: Icons.straighten_rounded,
                          text: distance.toStringAsFixed(1) + ' km',
                        ),
                      ),
                    if (duration != null)
                      Expanded(
                        child: _MiniHistoryMetric(
                          icon: Icons.timer_outlined,
                          text: duration.toString() + ' min',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _hubPaymentLabel(payment),
                    style: TextStyle(
                      color: _hubMutedText(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniHistoryMetric extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniHistoryMetric({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: _hubMutedText(context)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: _hubText(context),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

class _RouteLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _RouteLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: _hubText(context),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
}

class ExpressTripDetailPage extends StatefulWidget {
  final ExpressService service;
  final _HistoryEntry entry;
  final bool driver;

  const ExpressTripDetailPage({
    super.key,
    required this.service,
    required this.entry,
    required this.driver,
  });

  @override
  State<ExpressTripDetailPage> createState() => _ExpressTripDetailPageState();
}

class _ExpressTripDetailPageState extends State<ExpressTripDetailPage> {
  Map<String, dynamic>? counterpart;
  Map<String, dynamic>? payment;
  List<LatLng> roadRoute = const <LatLng>[];

  @override
  void initState() {
    super.initState();
    _loadExtra();
    _loadRoadRoute();
  }

  Future<void> _loadRoadRoute() async {
    final route = widget.entry.route;
    final aLat = _hubDouble(route['pickup_latitude']);
    final aLng = _hubDouble(route['pickup_longitude']);
    final bLat = _hubDouble(route['destination_latitude']);
    final bLng = _hubDouble(route['destination_longitude']);
    if (aLat == null || aLng == null || bLat == null || bLng == null) return;

    final from = LatLng(aLat, aLng);
    final to = LatLng(bLat, bLng);
    final resolved = await ExpressMapProvider.drivingRoute(from: from, to: to);
    if (!mounted) return;
    setState(() => roadRoute = resolved.points);
  }

  Future<void> _loadExtra() async {
    if (widget.entry.trip) {
      final otherId = widget.driver
          ? widget.entry.data['passenger_id']?.toString()
          : widget.entry.data['driver_id']?.toString();
      Map<String, dynamic>? nextCounterpart;
      if (otherId != null && otherId.isNotEmpty) {
        try {
          nextCounterpart = await widget.service.userById(otherId);
        } catch (_) {}
      }
      Map<String, dynamic>? nextPayment;
      try {
        final payments = await widget.service.myPayments();
        for (final row in payments) {
          if (row['trip_id']?.toString() == widget.entry.data['id']?.toString()) {
            nextPayment = row;
            break;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        counterpart = nextCounterpart;
        payment = nextPayment;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final route = entry.route;
    final status = entry.data['status'];
    final statusColor = _hubStatusColor(status);
    final fare = entry.trip
        ? entry.data['final_fare'] ?? route['proposed_fare']
        : route['proposed_fare'];
    final id = entry.data['id']?.toString() ?? '';
    final compactId = id.replaceAll('-', '');
    final code = compactId.isEmpty
        ? 'VIAJE'
        : compactId
            .substring(0, compactId.length < 8 ? compactId.length : 8)
            .toUpperCase();

    final pickupLat = _hubDouble(route['pickup_latitude']);
    final pickupLng = _hubDouble(route['pickup_longitude']);
    final destinationLat = _hubDouble(route['destination_latitude']);
    final destinationLng = _hubDouble(route['destination_longitude']);
    final pickupPoint = pickupLat != null && pickupLng != null
        ? LatLng(pickupLat, pickupLng)
        : null;
    final destinationPoint = destinationLat != null && destinationLng != null
        ? LatLng(destinationLat, destinationLng)
        : null;

    final distance = _hubDouble(route['route_distance_km']);
    final duration = route['route_duration_minutes'];
    final cancellationReason = entry.data['cancellation_reason'] ??
        route['cancellation_reason'];
    final paymentMethod = payment?['method'] ?? route['payment_method'];
    final currency = expressCurrencyCode(
      payment?['currency'] ?? route['currency'],
    );
    final commission = payment?['commission_amount'];
    final net = payment?['driver_net_amount'];

    return Scaffold(
      backgroundColor: _hubBackground(context),
      appBar: AppBar(
        backgroundColor: _hubSurface(context),
        foregroundColor: _hubText(context),
        surfaceTintColor: _hubSurface(context),
        title: Text(code, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: .14),
                  child: Icon(
                    status == 'cancelled' ? Icons.close_rounded : Icons.check_rounded,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hubStatusLabel(status),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        _hubDate(entry.data['completed_at'] ?? entry.data['created_at']),
                        style: TextStyle(
                          color: _hubMutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _hubMoney(fare, currency: currency),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          if (pickupPoint != null && destinationPoint != null) ...[
            const SizedBox(height: 18),
            const Text(
              'Mapa del viaje',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 230,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(
                      (pickupPoint.latitude + destinationPoint.latitude) / 2,
                      (pickupPoint.longitude + destinationPoint.longitude) / 2,
                    ),
                    initialZoom: 13.5,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                    ),
                  ),
                  children: [
                    const ExpressBaseTileLayer(),
                    const ExpressMapAttribution(),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: roadRoute.length >= 2
                              ? roadRoute
                              : <LatLng>[pickupPoint, destinationPoint],
                          strokeWidth: 5,
                          color: _hubBlue,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: pickupPoint,
                          width: 44,
                          height: 44,
                          child: const _DetailMapPin(
                            icon: Icons.my_location_rounded,
                            color: Color(0xFF22A559),
                          ),
                        ),
                        Marker(
                          point: destinationPoint,
                          width: 44,
                          height: 44,
                          child: const _DetailMapPin(
                            icon: Icons.location_on_rounded,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Ruta',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _HubCard(
            child: Column(
              children: [
                _DetailValue(
                  icon: Icons.my_location_rounded,
                  iconColor: const Color(0xFF22A559),
                  label: 'Origen',
                  value: _hubRouteAddress(route, addressKey: 'pickup_address', latitudeKey: 'pickup_latitude', longitudeKey: 'pickup_longitude', fallback: 'Origen no disponible'),
                ),
                const SizedBox(height: 15),
                _DetailValue(
                  icon: Icons.location_on_rounded,
                  iconColor: const Color(0xFFEF4444),
                  label: 'Destino',
                  value: _hubRouteAddress(route, addressKey: 'destination_address', latitudeKey: 'destination_latitude', longitudeKey: 'destination_longitude', fallback: 'Destino no disponible'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Detalles del viaje',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _HubCard(
            child: Column(
              children: [
                _DetailTableRow(label: 'Código de viaje', value: code),
                if (distance != null)
                  _DetailTableRow(
                    label: 'Distancia',
                    value: distance.toStringAsFixed(1) + ' km',
                  ),
                if (duration != null)
                  _DetailTableRow(
                    label: 'Duración estimada',
                    value: duration.toString() + ' min',
                  ),
                _DetailTableRow(
                  label: 'Tarifa',
                  value: _hubMoney(fare, currency: currency),
                ),
                _DetailTableRow(
                  label: 'Método de pago',
                  value: _hubPaymentLabel(paymentMethod),
                ),
                if (counterpart != null)
                  _DetailTableRow(
                    label: widget.driver ? 'Pasajero' : 'Conductor',
                    value: counterpart!['full_name']?.toString() ?? 'Usuario Express',
                  ),
                if (widget.driver && commission != null)
                  _DetailTableRow(
                    label: 'Comisión Express',
                    value: _hubMoney(commission, currency: currency),
                  ),
                if (widget.driver && net != null)
                  _DetailTableRow(
                    label: 'Ganancia neta',
                    value: _hubMoney(net, currency: currency),
                  ),
                if (status == 'cancelled')
                  _DetailTableRow(
                    label: 'Motivo de cancelación',
                    value: cancellationReason?.toString().trim().isNotEmpty == true
                        ? cancellationReason.toString()
                        : 'Sin motivo registrado',
                    danger: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExpressCenterPage(service: widget.service),
              ),
            ),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Reportar problema'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailMapPin extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _DetailMapPin({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 8),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      );
}

class _DetailValue extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _DetailValue({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _hubMutedText(context),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      );
}

class _DetailTableRow extends StatelessWidget {
  final String label;
  final String value;
  final bool danger;

  const _DetailTableRow({
    required this.label,
    required this.value,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _hubBorder(context)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: _hubMutedText(context)),
              ),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: danger
                      ? const Color(0xFFDC2626)
                      : _hubText(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
}

class _WalletBundle {
  final Map<String, dynamic> wallet;
  final List<Map<String, dynamic>> movements;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> topups;
  final Map<String, dynamic> settings;
  final Map<String, dynamic> subscriptionCatalog;
  final Map<String, dynamic> subscriptionState;

  const _WalletBundle({
    required this.wallet,
    required this.movements,
    required this.payments,
    required this.topups,
    required this.settings,
    required this.subscriptionCatalog,
    required this.subscriptionState,
  });
}

class ExpressWalletPage extends StatefulWidget {
  final ExpressService service;
  final bool driver;

  const ExpressWalletPage({
    super.key,
    required this.service,
    required this.driver,
  });

  @override
  State<ExpressWalletPage> createState() => _ExpressWalletPageState();
}

class _ExpressWalletPageState extends State<ExpressWalletPage> {
  int refresh = 0;
  int? payingPlanId;

  Future<_WalletBundle> _load() async {
    final walletFuture = widget.service.myWallet();
    final movementFuture = widget.service.walletTransactions();
    final paymentFuture = widget.service.myPayments();
    final topupFuture = widget.service.walletTopupRequests();
    final settingsFuture = widget.service.appSettings();
    final catalogFuture = widget.driver
        ? widget.service.driverSubscriptionCatalog()
        : Future.value(<String, dynamic>{});
    final stateFuture = widget.driver
        ? widget.service.driverSubscriptionState()
        : Future.value(<String, dynamic>{});
    return _WalletBundle(
      wallet: await walletFuture,
      movements: await movementFuture,
      payments: await paymentFuture,
      topups: await topupFuture,
      settings: await settingsFuture,
      subscriptionCatalog: await catalogFuture,
      subscriptionState: await stateFuture,
    );
  }

  Future<void> _requestTopup() async {
    final controller = TextEditingController();
    final amount = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recargar billetera'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa el monto. La solicitud quedará pendiente hasta que Express la apruebe.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monto',
                hintText: '100.00',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Más adelante este botón se conectará al pago QR automático.',
              style: TextStyle(color: _hubMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = num.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              if (value != null && value >= 1 && value <= 5000) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Solicitar recarga'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;

    try {
      await widget.service.requestWalletTopup(amount);
      if (!mounted) return;
      setState(() => refresh++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recarga enviada. Quedó pendiente de aprobación por Express.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo solicitar la recarga: $e')),
      );
    }
  }


  Future<void> _paySubscriptionWithWallet(
    Map<String, dynamic> plan,
  ) async {
    final rawId = plan['id'];
    final planId =
        rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '');
    if (planId == null || payingPlanId != null) return;

    final currency = plan['currency_code']?.toString() ?? '';
    final amount = _hubDouble(plan['amount']) ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pagar suscripción con billetera'),
        content: Text(
          'Se descontarán ' +
              expressMoney(amount, currency) +
              ' de tu Billetera Express para activar “' +
              (plan['name']?.toString() ?? 'este plan') +
              '”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar pago'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => payingPlanId = planId);
    try {
      final result =
          await widget.service.payDriverSubscriptionWithWallet(planId);
      if (!mounted) return;
      setState(() {
        payingPlanId = null;
        refresh++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Suscripción activada. Nuevo saldo: ' +
                expressMoney(
                  _hubDouble(result['balance_after']) ?? 0,
                  result['currency_code']?.toString() ?? currency,
                ) +
                '.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => payingPlanId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ExpressRuntimeChannel.userSafeError(
              e,
              fallback: 'No se pudo pagar la suscripción.',
            ),
          ),
        ),
      );
    }
  }

  Widget _subscriptionWalletCard(_WalletBundle data) {
    final catalog = data.subscriptionCatalog;
    final state = data.subscriptionState;
    final featureEnabled =
        catalog['enabled'] == true || state['feature_enabled'] == true;
    final zoneRaw = catalog['zone'];
    final zone = zoneRaw is Map
        ? Map<String, dynamic>.from(zoneRaw)
        : <String, dynamic>{};
    final zoneName = zone['name']?.toString() ??
        state['zone_name']?.toString() ??
        'tu zona';
    final providerKey =
        catalog['payment_provider_key']?.toString() ?? '';
    final providerLabel =
        catalog['payment_provider_label']?.toString() ??
        (providerKey == 'mercado_pago'
            ? 'Mercado Pago'
            : providerKey == 'veripagos_qr'
                ? 'QR Bolivia · VeriPagos'
                : 'el método configurado');
    final active = state['usable'] == true;
    final currentPlan = state['plan_name']?.toString();
    final expiresAt = state['expires_at'];

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hubSurface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _hubBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: _hubBlue),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Suscripción · ' + zoneName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (active)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F8EF),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'ACTIVA',
                    style: TextStyle(
                      color: Color(0xFF14804A),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!featureEnabled)
            Text(
              ExpressRuntimeChannel.technicalOr(
                production:
                    'Las suscripciones no están disponibles por ahora.',
                preview:
                    'Las suscripciones están desactivadas en $zoneName.',
              ),
              style: TextStyle(color: _hubMutedText(context)),
            )
          else ...[
            if (active)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _hubSoftSurface(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  (currentPlan ?? 'Plan activo') +
                      ' · vence ' +
                      _hubDate(expiresAt),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _hubSoftSurface(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                ExpressRuntimeChannel.technicalOr(
                  production:
                      'Para comprar o renovar un plan usa Mi perfil → Suscripción.',
                  preview:
                      'Las suscripciones de $zoneName se pagan con $providerLabel. La billetera conserva únicamente saldo y movimientos de su propia moneda. Para comprar o renovar un plan usa Mi perfil → Suscripción.',
                ),
                style: TextStyle(
                  color: _hubMutedText(context),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hubBackground(context),
      appBar: AppBar(
        backgroundColor: _hubSurface(context),
        foregroundColor: _hubText(context),
        surfaceTintColor: _hubSurface(context),
        title: Text(
          widget.driver ? 'Mi billetera' : 'Pagos y billetera',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: FutureBuilder<_WalletBundle>(
        key: ValueKey(refresh),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _HubError(
              text: snapshot.error.toString(),
              onRetry: () => setState(() => refresh++),
            );
          }
          final data = snapshot.data!;
          final balance = _hubDouble(data.wallet['balance']) ?? 0;
          final currency =
              data.wallet['currency']?.toString().toUpperCase() ?? 'BOB';
          final zoneRaw = data.subscriptionCatalog['zone'];
          final zone = zoneRaw is Map
              ? Map<String, dynamic>.from(zoneRaw)
              : <String, dynamic>{};
          final zoneCurrency =
              zone['currency_code']?.toString().toUpperCase() ?? currency;
          final zoneName = zone['name']?.toString() ?? 'tu zona';
          final walletCurrencyMismatch =
              widget.driver && zoneCurrency != currency;
          final commissionPct = _hubDouble(data.settings['commission_percent']) ?? 0;
          num earnings = 0;
          num commissions = 0;
          for (final row in data.movements) {
            final amount = _hubDouble(row['amount']) ?? 0;
            if (row['type'] == 'earning') earnings += amount;
            if (row['type'] == 'commission') commissions += amount.abs();
          }
          final walletEnabled = data.settings['allow_wallet'] == true;
          final cardEnabled = data.settings['allow_card'] == true;
          final pendingTopups = data.topups
              .where((row) => row['status']?.toString() == 'pending')
              .toList();

          return RefreshIndicator(
            onRefresh: () async => setState(() => refresh++),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B1739), _hubBlue],
                    ),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            widget.driver ? 'Billetera del conductor' : 'Billetera Express',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        expressMoney(balance, currency),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        balance < 0 ? 'Saldo por regularizar' : 'Saldo disponible',
                        style: const TextStyle(color: Color(0xFFDCEAFF)),
                      ),
                      if (widget.driver) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                commissionPct == 0
                                    ? 'Comisión de lanzamiento: 0%'
                                    : 'Comisión configurada: ' +
                                        commissionPct.toStringAsFixed(1) +
                                        '%',
                                style: const TextStyle(
                                  color: Color(0xFFDCEAFF),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed:
                                  walletCurrencyMismatch ? null : _requestTopup,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Recargar'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: _hubBlue,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (walletCurrencyMismatch) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _hubDarkMode(context)
                          ? const Color(0xFF2A2418)
                          : const Color(0xFFFFF8E8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _hubDarkMode(context)
                            ? const Color(0xFF6B5420)
                            : const Color(0xFFFEDC89),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.currency_exchange_rounded,
                          color: Color(0xFFB54708),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tu saldo actual está en ' +
                                currency +
                                ', pero ' +
                                zoneName +
                                ' opera en ' +
                                zoneCurrency +
                                '. El saldo se conserva y no se convierte ni se mezcla automáticamente. Las recargas quedan bloqueadas hasta usar una billetera de la moneda de la zona.',
                            style: const TextStyle(
                              color: Color(0xFFB54708),
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (widget.driver && pendingTopups.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _hubDarkMode(context)
                          ? const Color(0xFF2A2418)
                          : const Color(0xFFFFF8E8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _hubDarkMode(context)
                            ? const Color(0xFF6B5420)
                            : const Color(0xFFFEDC89),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          color: Color(0xFFB54708),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Recarga pendiente: ' +
                                _hubMoney(
                                  pendingTopups.first['amount'],
                                  currency: pendingTopups.first['currency'] ?? currency,
                                ) +
                                '. Te avisaremos cuando sea aprobada.',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (widget.driver)
                  Row(
                    children: [
                      Expanded(
                        child: _WalletMetric(
                          label: 'Ingresos',
                          value: _hubMoney(earnings, currency: currency),
                          icon: Icons.south_west_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WalletMetric(
                          label: 'Comisiones',
                          value: _hubMoney(commissions, currency: currency),
                          icon: Icons.percent_rounded,
                        ),
                      ),
                    ],
                  ),
                if (!widget.driver) ...[
                  _PaymentMethodSummary(
                    cash: data.settings['allow_cash'] != false,
                    card: cardEnabled,
                    wallet: walletEnabled,
                    onOpen: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpressPaymentMethodsPage(
                          service: widget.service,
                        ),
                      ),
                    ),
                  ),
                ],
                if (widget.driver) _subscriptionWalletCard(data),
                const SizedBox(height: 22),
                const Text(
                  'Movimientos',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                if (data.movements.isEmpty)
                  const _HubInfo(
                    icon: Icons.receipt_long_outlined,
                    title: 'Sin movimientos todavía',
                    text: 'Aquí aparecerán ingresos, pagos, comisiones y ajustes de tu billetera.',
                  )
                else
                  ...data.movements.map((row) => _WalletMovement(row: row, currency: currency)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WalletMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _WalletMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => _HubCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _hubDarkMode(context)
                  ? const Color(0xFF17315E)
                  : const Color(0xFFEAF2FF),
              child: Icon(icon, color: _hubBlue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: _hubMutedText(context),
                      fontSize: 11,
                    ),
                  ),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _WalletMovement extends StatelessWidget {
  final Map<String, dynamic> row;
  final String currency;

  const _WalletMovement({required this.row, required this.currency});

  @override
  Widget build(BuildContext context) {
    final amount = _hubDouble(row['amount']) ?? 0;
    final positive = amount >= 0;
    final type = row['type']?.toString();
    String label;
    switch (type) {
      case 'earning':
        label = 'Ingreso por viaje';
        break;
      case 'commission':
        label = 'Comisión Express';
        break;
      case 'payment':
        label = 'Pago de servicio';
        break;
      case 'refund':
        label = 'Devolución';
        break;
      case 'topup':
        label = 'Recarga';
        break;
      default:
        label = 'Ajuste de billetera';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _HubCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: (positive ? const Color(0xFF16A34A) : const Color(0xFFDC2626))
                  .withValues(alpha: .10),
              child: Icon(
                positive ? Icons.add_rounded : Icons.remove_rounded,
                color: positive ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(
                    row['reference']?.toString() ?? _hubDate(row['created_at']),
                    style: const TextStyle(color: _hubMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              (positive ? '+' : '-') + expressMoney(amount.abs(), currency),
              style: TextStyle(
                color: positive ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExpressPaymentMethodsPage extends StatefulWidget {
  final ExpressService service;
  final bool driver;

  const ExpressPaymentMethodsPage({
    super.key,
    required this.service,
    this.driver = false,
  });

  @override
  State<ExpressPaymentMethodsPage> createState() =>
      _ExpressPaymentMethodsPageState();
}

class _ExpressPaymentMethodsPageState
    extends State<ExpressPaymentMethodsPage> {
  int revision = 0;
  bool saving = false;
  String? passengerSelected;
  Set<String>? driverSelected;

  Future<({
    List<Map<String, dynamic>> methods,
    Map<String, dynamic>? user,
    Map<String, dynamic>? driverProfile,
  })> _load() async {
    final methodsFuture = widget.service.myRidePaymentMethods();
    final userFuture = widget.service.myUser(forceRefresh: true);
    final driverFuture = widget.driver
        ? widget.service.myDriverProfile(forceRefresh: true)
        : Future<Map<String, dynamic>?>.value(null);
    return (
      methods: await methodsFuture,
      user: await userFuture,
      driverProfile: await driverFuture,
    );
  }

  Set<String> _acceptedFromProfile(Map<String, dynamic>? profile) {
    final raw = profile?['accepted_payment_methods'];
    if (raw is List) {
      return raw.map((value) => value.toString()).toSet();
    }
    return <String>{'cash', 'driver_qr'};
  }

  Future<void> _selectPassenger(
    String method,
    String current,
  ) async {
    if (saving || method == current) return;
    setState(() => saving = true);
    try {
      await widget.service.setPreferredRidePaymentMethod(method);
      if (!mounted) return;
      setState(() {
        passengerSelected = method;
        saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Método preferido actualizado.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ExpressRuntimeChannel.userSafeError(
              e,
              fallback: 'No se pudo cambiar el método de pago.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _toggleDriver(
    String method,
    Set<String> current,
  ) async {
    if (saving) return;
    final next = <String>{...current};
    if (next.contains(method)) {
      if (next.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El conductor debe aceptar al menos un método de cobro.',
            ),
          ),
        );
        return;
      }
      next.remove(method);
    } else {
      next.add(method);
    }

    setState(() => saving = true);
    try {
      await widget.service.setDriverPaymentMethods(next.toList()..sort());
      if (!mounted) return;
      setState(() {
        driverSelected = next;
        saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Métodos de cobro del conductor actualizados.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ExpressRuntimeChannel.userSafeError(
              e,
              fallback: 'No se pudieron guardar los métodos de cobro.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hubBackground(context),
      appBar: AppBar(
        backgroundColor: _hubSurface(context),
        foregroundColor: _hubText(context),
        surfaceTintColor: _hubSurface(context),
        title: Text(
          widget.driver ? 'Métodos de cobro' : 'Métodos de pago',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: FutureBuilder<
          ({
            List<Map<String, dynamic>> methods,
            Map<String, dynamic>? user,
            Map<String, dynamic>? driverProfile,
          })>(
        key: ValueKey(revision),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  ExpressRuntimeChannel.userSafeError(
                    snapshot.error,
                    fallback: 'No pudimos cargar los métodos de pago.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data;
          final methods =
              data?.methods ?? const <Map<String, dynamic>>[];
          final availableKeys = methods
              .map((row) => row['provider_key']?.toString() ?? '')
              .where((key) => key.isNotEmpty)
              .toSet();

          final storedPassenger =
              data?.user?['preferred_payment_method']?.toString() ?? 'cash';
          final passengerMethod = passengerSelected ??
              (availableKeys.contains(storedPassenger)
                  ? storedPassenger
                  : (methods.isNotEmpty
                      ? methods.first['provider_key']?.toString() ?? 'cash'
                      : 'cash'));

          final storedDriver = _acceptedFromProfile(data?.driverProfile)
              .intersection(availableKeys);
          final accepted = driverSelected ??
              (storedDriver.isNotEmpty
                  ? storedDriver
                  : (availableKeys.isNotEmpty
                      ? <String>{availableKeys.first}
                      : <String>{}));

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.driver
                    ? 'Métodos que aceptas en viajes'
                    : 'Método preferido para viajes',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.driver
                    ? 'Puedes aceptar uno o varios. Solo recibirás solicitudes compatibles con tu selección.'
                    : 'Este método quedará seleccionado por defecto al pedir un viaje. Puedes cambiarlo antes de confirmar.',
                style: TextStyle(
                  color: _hubMutedText(context),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              if (methods.isEmpty)
                _HubInfo(
                  icon: Icons.info_outline_rounded,
                  title: ExpressRuntimeChannel.previewMode
                      ? 'Sin métodos activos'
                      : 'Sin métodos disponibles',
                  text: ExpressRuntimeChannel.previewMode
                      ? 'Administración todavía no habilitó un método de pago para viajes en tu zona.'
                      : 'No hay métodos de pago disponibles por ahora.',
                )
              else
                for (var i = 0; i < methods.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final method = methods[i];
                      final key =
                          method['provider_key']?.toString() ?? '';
                      final label =
                          method['display_name']?.toString() ??
                              _hubPaymentLabel(key);
                      final directQr = key == 'driver_qr';
                      final cash = key == 'cash';
                      final selected = widget.driver
                          ? accepted.contains(key)
                          : passengerMethod == key;

                      return _PaymentOption(
                        icon: directQr
                            ? Icons.qr_code_2_rounded
                            : cash
                                ? Icons.payments_rounded
                                : Icons
                                    .account_balance_wallet_outlined,
                        title: label,
                        subtitle: directQr
                            ? (widget.driver
                                ? ExpressRuntimeChannel.technicalOr(
                                    production: 'Recibe el pago directamente en tu QR.',
                                    preview: 'El pasajero paga directamente a tu QR. La cuenta del administrador no interviene.',
                                  )
                                : ExpressRuntimeChannel.technicalOr(
                                    production: 'Paga directamente al QR que te indique el conductor.',
                                    preview: 'Paga directamente al QR que te indique el conductor. Express no cobra este viaje.',
                                  ))
                            : cash
                                ? 'El pago se entrega directamente al conductor al finalizar el viaje.'
                                : ExpressRuntimeChannel.technicalOr(
                                    production: 'Método disponible para este viaje.',
                                    preview: 'Método habilitado por administración para tu zona.',
                                  ),
                        color: directQr
                            ? const Color(0xFF0E9384)
                            : cash
                                ? const Color(0xFF22C55E)
                                : const Color(0xFF2563EB),
                        enabled: true,
                        selected: selected,
                        selectionLabel: widget.driver
                            ? (selected ? 'Aceptado' : 'No aceptado')
                            : (selected ? 'Preferido' : 'Seleccionar'),
                        onTap: saving
                            ? null
                            : () => widget.driver
                                ? _toggleDriver(key, accepted)
                                : _selectPassenger(
                                    key,
                                    passengerMethod,
                                  ),
                      );
                    },
                  ),
                  if (i != methods.length - 1)
                    const SizedBox(height: 12),
                ],
              if (ExpressRuntimeChannel.previewMode) ...[
                const SizedBox(height: 24),
                const _HubInfo(
                  icon: Icons.info_outline_rounded,
                  title: 'El método depende de tu zona',
                  text:
                      'Chile usa efectivo para viajes. Bolivia puede usar efectivo o QR del conductor. Mercado Pago y las pasarelas de Express quedan reservadas para suscripciones y recargas.',
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final bool selected;
  final String? selectionLabel;
  final VoidCallback? onTap;

  const _PaymentOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.enabled,
    this.selected = false,
    this.selectionLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : .62,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _hubSurface(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? color : _hubBorder(context),
                  width: selected ? 1.8 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: color, size: 31),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (!enabled) ...[
                              const SizedBox(width: 8),
                              const _PaymentStatusChip(
                                label: 'Próximamente',
                                active: false,
                              ),
                            ] else if (selectionLabel != null) ...[
                              const SizedBox(width: 8),
                              _PaymentStatusChip(
                                label: selectionLabel!,
                                active: selected,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: _hubMutedText(context),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (enabled && onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected ? color : _hubMutedText(context),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PaymentStatusChip extends StatelessWidget {
  final String label;
  final bool active;

  const _PaymentStatusChip({
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFEAF2FF)
              : (_hubDarkMode(context)
                  ? const Color(0xFF2A2D33)
                  : const Color(0xFFF2F4F7)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? _hubBlue : _hubMutedText(context),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _PaymentMethodSummary extends StatelessWidget {
  final bool cash;
  final bool card;
  final bool wallet;
  final VoidCallback onOpen;

  const _PaymentMethodSummary({
    required this.cash,
    required this.card,
    required this.wallet,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => _HubCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Métodos de pago',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              cash && !card && !wallet
                  ? 'Efectivo activo · tarjeta y billetera próximamente'
                  : 'Métodos disponibles configurados por Express',
              style: const TextStyle(color: _hubMuted),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.credit_card_rounded),
              label: const Text('Ver métodos'),
            ),
          ],
        ),
      );
}

class _ProfileBundle {
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? driverProfile;
  final List<Map<String, dynamic>> trips;
  final Map<String, dynamic> settings;
  final Map<String, dynamic> manualKyc;

  const _ProfileBundle({
    required this.user,
    required this.driverProfile,
    required this.trips,
    this.settings = const <String, dynamic>{},
    this.manualKyc = const <String, dynamic>{},
  });
}

class ExpressProfileHubPage extends StatefulWidget {
  final ExpressService service;
  final bool driver;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;
  final VoidCallback onSavedAddresses;
  final VoidCallback onSafety;

  const ExpressProfileHubPage({
    super.key,
    required this.service,
    required this.driver,
    required this.onSwitchMode,
    required this.onExit,
    required this.onSavedAddresses,
    required this.onSafety,
  });

  @override
  State<ExpressProfileHubPage> createState() => _ExpressProfileHubPageState();
}

class _ExpressProfileHubPageState extends State<ExpressProfileHubPage> {
  int refresh = 0;
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  Future<_ProfileBundle> _load() async {
    final userFuture = widget.service.myUser();
    final tripsFuture = widget.service.myTrips();
    final settingsFuture = widget.service.appSettings(forceRefresh: true);
    Map<String, dynamic>? driverProfile;
    try {
      // El perfil de conductor es una capacidad opcional de la misma cuenta.
      // También lo cargamos en modo Pasajero para mostrar correctamente el
      // onboarding/estado de aprobación sin crear otra identidad.
      driverProfile = await widget.service.myDriverProfile(forceRefresh: true);
    } catch (_) {}
    Map<String,dynamic> manualKyc=const <String,dynamic>{};
    if(driverProfile?['country_code']?.toString().toUpperCase()=='BO'){
      try {
        final raw=await Supabase.instance.client.rpc(
          'driver_kyc_bolivia_review_state');
        if(raw is Map) manualKyc=Map<String,dynamic>.from(raw);
      } catch (_) {
        // Keep account menu available even when KYC service is offline.
      }
    }
    return _ProfileBundle(
      user: await userFuture,
      driverProfile: driverProfile,
      trips: await tripsFuture,
      settings: await settingsFuture,
      manualKyc:manualKyc,
    );
  }

  Future<void> _edit(Map<String, dynamic>? user) async {
    final name = TextEditingController(
      text: user?['full_name']?.toString() ?? '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar perfil'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Nombre completo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final nextName = name.text.trim();
    name.dispose();
    if (save != true || nextName.isEmpty || !mounted) return;
    await widget.service.updateProfile(fullName: nextName);
    if (mounted) setState(() => refresh++);
  }

  void _notificationInfo() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Notificaciones'),
        content: const Text(
          'Express usa notificaciones para solicitudes, ofertas, llegada del conductor, estados del viaje, seguridad y movimientos de billetera. Los permisos del sistema se administran desde Android.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_ProfileBundle>(
        key: ValueKey(refresh),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ??
              const _ProfileBundle(
                user: null,
                driverProfile: null,
                trips: <Map<String, dynamic>>[],
                settings: <String, dynamic>{},
              );
          final user = data.user;
          final driverApproval = data.driverProfile?['approval_status']
              ?.toString()
              .trim()
              .toLowerCase();
          final driverOnboardingCompleted =
              data.driverProfile?['onboarding_completed_at']
                      ?.toString()
                      .trim()
                      .isNotEmpty ==
                  true;
          final manualKycRejected =
              data.manualKyc['needs_correction']==true;
          final driverRejected =
              driverApproval == 'rejected' || manualKycRejected;
          final email = Supabase.instance.client.auth.currentUser?.email ?? '';
          final name = user?['full_name']?.toString().trim();
          final displayName = name?.isNotEmpty == true ? name! : 'Usuario Express';
          final completed = data.trips.where((row) => row['status'] == 'completed').length;
          final rating = widget.driver
              ? (data.driverProfile?['rating']?.toString() ?? '5.0')
              : '—';
          final created = DateTime.tryParse(user?['created_at']?.toString() ?? '');
          final memberYear = created?.year.toString() ?? DateTime.now().year.toString();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Perfil',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ayuda',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpressHelpPage(
                          service: widget.service,
                          driver: widget.driver,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.help_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: CircleAvatar(
                  radius: 43,
                  backgroundColor: _hubDarkMode(context)
                      ? const Color(0xFF17315E)
                      : const Color(0xFFEAF2FF),
                  child: const Icon(Icons.person_rounded, size: 45, color: _hubBlue),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              if (email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    email,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _hubMutedText(context)),
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _ProfileStat(value: completed.toString(), label: 'Viajes')),
                  Expanded(child: _ProfileStat(value: rating, label: 'Calificación')),
                  Expanded(child: _ProfileStat(value: memberYear, label: 'Miembro desde')),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Cuenta', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              _ProfileMenu(
                items: [
                  _ProfileAction(
                    icon: Icons.person_outline_rounded,
                    title: 'Editar perfil',
                    onTap: () => _edit(user),
                  ),
                  _ProfileAction(
                    icon: Icons.credit_card_outlined,
                    title: 'Métodos de pago',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ExpressPaymentMethodsPage(
                              service: widget.service,
                              driver: widget.driver,
                            ),
                      ),
                    ),
                  ),
                  _ProfileAction(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Mi billetera',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpressWalletPage(
                          service: widget.service,
                          driver: widget.driver,
                        ),
                      ),
                    ),
                  ),
                  if (widget.driver)
                    _ProfileAction(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Suscripción',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DriverSubscriptionPage(),
                        ),
                      ),
                    ),
                  if (widget.driver)
                    _ProfileAction(
                      icon: Icons.military_tech_outlined,
                      title: 'Mi prioridad',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DriverPriorityPage(
                            service: widget.service,
                          ),
                        ),
                      ),
                    ),
                  if (!widget.driver)
                    _ProfileAction(
                      icon: Icons.location_on_outlined,
                      title: 'Lugares guardados',
                      onTap: widget.onSavedAddresses,
                    ),
                  _ProfileAction(
                    icon: Icons.history_rounded,
                    title: 'Historial de viajes',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpressHistoryPage(
                          service: widget.service,
                          driver: widget.driver,
                        ),
                      ),
                    ),
                  ),
                  _ProfileAction(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notificaciones',
                    onTap: _notificationInfo,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Soporte y seguridad', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              _ProfileMenu(
                items: [
                  _ProfileAction(
                    icon: Icons.help_outline_rounded,
                    title: 'Ayuda',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpressHelpPage(
                          service: widget.service,
                          driver: widget.driver,
                        ),
                      ),
                    ),
                  ),
                  _ProfileAction(
                    icon: Icons.shield_outlined,
                    title: 'Seguridad y SOS',
                    onTap: widget.onSafety,
                  ),
                  _ProfileAction(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacidad y datos',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpressPrivacyDataPage(
                          service: widget.service,
                        ),
                      ),
                    ),
                  ),
                  if (widget.driver)
                    _ProfileAction(
                      icon: Icons.directions_car_outlined,
                      title: 'Vehículo y documentos',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DriverVehicleDocumentsPage(
                            service: widget.service,
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => refresh++);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _ProfileMenu(
                items: [
                  _ProfileAction(
                    icon: Icons.swap_horiz_rounded,
                    title: widget.driver
                        ? 'Cambiar a modo Pasajero'
                        : data.driverProfile == null
                            ? 'Conducir con Express'
                            : driverApproval == 'approved'
                                ? 'Cambiar a modo Conductor'
                                : manualKycRejected
                                    ? 'Corregir documentos'
                                    : driverApproval=='rejected'
                                        ? 'Revisar registro de conductor'
                                        : driverOnboardingCompleted
                                            ? 'Solicitud de conductor en revisión'
                                            : 'Continuar registro de conductor',
                    onTap: manualKycRejected
                      ? ()=>Navigator.push(context,
                          MaterialPageRoute(builder:(_)=>
                            const DriverKycCorrectionPage()),
                        ).then((_){
                          if(mounted) setState(()=>refresh++);
                        })
                      : widget.onSwitchMode,
                  ),
                  _ProfileAction(
                    icon: Icons.logout_rounded,
                    title: 'Cerrar sesión',
                    danger: true,
                    onTap: widget.onExit,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FutureBuilder<PackageInfo>(
                future: _packageInfoFuture,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  final channel = ExpressRuntimeChannel.previewMode
                      ? 'Preview'
                      : 'Producción';
                  final label = info == null
                      ? 'Versión… · $channel'
                      : 'Versión ${info.version} (${info.buildNumber}) · $channel';
                  return Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: _hubMutedText(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}


class ExpressPrivacyDataPage extends StatefulWidget {
  final ExpressService service;

  const ExpressPrivacyDataPage({
    super.key,
    required this.service,
  });

  @override
  State<ExpressPrivacyDataPage> createState() => _ExpressPrivacyDataPageState();
}

class _ExpressPrivacyDataPageState extends State<ExpressPrivacyDataPage> {
  static final Uri _privacyUri = Uri.parse(
    'https://expressviajes.online/privacidad/',
  );
  static final Uri _deleteUri = Uri.parse(
    'https://expressviajes.online/eliminar-cuenta/',
  );

  bool deleting = false;

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    if (deleting) return;

    final continueDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
        title: const Text('Eliminar cuenta permanentemente'),
        content: const Text(
          'Esta acción elimina tu cuenta de Express y los datos personales '
          'asociados, incluyendo perfil, direcciones guardadas, tokens de '
          'notificación, soporte, calificaciones y actividad vinculada a tu '
          'cuenta. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (continueDelete != true || !mounted) return;

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmación final'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escribe ELIMINAR para confirmar que deseas borrar tu cuenta.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Escribe ELIMINAR',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(
                dialogContext,
                controller.text.trim().toUpperCase() == 'ELIMINAR',
              );
            },
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (confirmed != true || !mounted) {
      if (confirmed == false && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La confirmación no coincide. No se eliminó la cuenta.'),
          ),
        );
      }
      return;
    }

    setState(() => deleting = true);
    try {
      await widget.service.deleteMyAccount();
      try {
        await Supabase.instance.client.auth.signOut(
          scope: SignOutScope.local,
        );
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tu cuenta y datos asociados fueron eliminados.'),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar la cuenta. Intenta nuevamente o contacta a soporte.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hubBackground(context),
      appBar: AppBar(
        title: const Text('Privacidad y datos'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          _HubCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tus datos en Express',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Express utiliza datos de cuenta, ubicación y servicio para '
                  'operar viajes, seguridad, soporte, notificaciones y las '
                  'funciones que solicitas. Puedes consultar la política '
                  'completa en cualquier momento.',
                  style: TextStyle(
                    color: _hubMutedText(context),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => _open(_privacyUri),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Ver política de privacidad'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _HubCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Eliminación de cuenta',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Puedes eliminar tu cuenta directamente desde esta pantalla. '
                  'También existe una página pública con instrucciones para '
                  'solicitar la eliminación fuera de la aplicación.',
                  style: TextStyle(
                    color: _hubMutedText(context),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => _open(_deleteUri),
                  icon: const Icon(Icons.language_rounded),
                  label: const Text('Ver página de eliminación'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: deleting ? null : _deleteAccount,
                  icon: deleting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_forever_outlined),
                  label: Text(
                    deleting ? 'Eliminando…' : 'Eliminar mi cuenta',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _HubCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.mail_outline_rounded, color: _hubBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Consultas de privacidad: soporte@expressdelivery.pro',
                    style: TextStyle(
                      color: _hubMutedText(context),
                      height: 1.45,
                    ),
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

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;

  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: _hubMutedText(context),
              fontSize: 10,
            ),
          ),
        ],
      );
}

class _ProfileAction {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  const _ProfileAction({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.danger = false,
  });
}

class _ProfileMenu extends StatelessWidget {
  final List<_ProfileAction> items;

  const _ProfileMenu({required this.items});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _hubSurface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hubBorder(context)),
        ),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              ListTile(
                leading: Icon(
                  items[i].icon,
                  color: items[i].danger
                      ? const Color(0xFFF87171)
                      : _hubMutedText(context),
                ),
                title: Text(
                  items[i].title,
                  style: TextStyle(
                    color: items[i].danger
                        ? const Color(0xFFF87171)
                        : _hubText(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: items[i].subtitle == null
                    ? null
                    : Text(
                        items[i].subtitle!,
                        style: TextStyle(color: _hubMutedText(context)),
                      ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: _hubMutedText(context),
                ),
                onTap: items[i].onTap,
              ),
              if (i != items.length - 1)
                Divider(
                  height: 1,
                  indent: 55,
                  color: _hubBorder(context),
                ),
            ],
          ],
        ),
      );
}

class ExpressHelpPage extends StatelessWidget {
  final ExpressService service;
  final bool driver;

  const ExpressHelpPage({
    super.key,
    required this.service,
    required this.driver,
  });

  List<Map<String, String>> get _questions {
    if (driver) {
      return const [
        {
          'q': '¿Cómo recibo solicitudes?',
          'a': 'Ponte En línea. Cuando llegue una solicitud compatible, Express abrirá el detalle automáticamente y también enviará una notificación.'
        },
        {
          'q': '¿Qué hago cuando aceptan mi oferta?',
          'a': 'Ve al punto de recogida siguiendo la ruta. Al llegar toca “Llegué”; el pasajero verá un contador de 5 minutos y podrá avisarte con “Ya voy”.'
        },
        {
          'q': '¿Cómo inicio el viaje?',
          'a': 'Cuando el pasajero aborde, solicita su PIN de 4 dígitos. El viaje solo inicia si el PIN es correcto.'
        },
        {
          'q': '¿Cómo funciona mi billetera?',
          'a': 'Los pagos electrónicos se acreditarán a tu billetera. En efectivo, la comisión configurada por Express se descuenta de la billetera.'
        },
        {
          'q': '¿Qué comisión cobra Express?',
          'a': 'La comisión vigente puede variar según tu zona o promociones. Tu billetera muestra cada descuento como un movimiento separado.'
        },
        {
          'q': '¿Puedo cancelar un viaje?',
          'a': 'Sí, antes de iniciar el viaje. Express pedirá un motivo y lo guardará en el detalle del historial.'
        },
      ];
    }
    return const [
      {
        'q': '¿Cómo pido un viaje?',
        'a': 'Selecciona origen y destino, confirma la recogida, elige la categoría y la tarifa. Express buscará conductores cercanos.'
      },
      {
        'q': '¿Cómo sé dónde está el conductor?',
        'a': 'Cuando el conductor esté asignado, el mapa muestra su ubicación y la ruta hacia la recogida. Durante el viaje muestra conductor → destino.'
      },
      {
        'q': '¿Qué pasa cuando el conductor llega?',
        'a': 'Recibirás una notificación y un contador de 5 minutos. Toca “Ya voy” para avisarle al conductor que estás bajando.'
      },
      {
        'q': '¿Para qué sirve el PIN?',
        'a': 'El PIN confirma que abordaste el vehículo correcto. Compártelo con el conductor únicamente cuando estés listo para iniciar el viaje.'
      },
      {
        'q': '¿Qué métodos de pago acepta Express?',
        'a': 'La aplicación muestra únicamente los métodos de pago disponibles para tu viaje y tu zona.'
      },
      {
        'q': '¿Dónde veo mis viajes anteriores?',
        'a': 'Abre Perfil → Historial de viajes o la pestaña Historial. Puedes abrir cada viaje para revisar ruta, tarifa, pago y estado.'
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hubBackground(context),
      appBar: AppBar(
        backgroundColor: _hubSurface(context),
        foregroundColor: _hubText(context),
        surfaceTintColor: _hubSurface(context),
        title: const Text('Ayuda', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
        children: [
          const Text(
            'Preguntas frecuentes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ..._questions.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: _hubSurface(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _hubBorder(context)),
                ),
                child: ExpansionTile(
                  iconColor: _hubMutedText(context),
                  collapsedIconColor: _hubMutedText(context),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(
                    item['q']!,
                    style: TextStyle(
                      color: _hubText(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item['a']!,
                        style: TextStyle(
                          color: _hubMutedText(context),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _HubCard(
            child: Column(
              children: [
                Icon(
                  Icons.support_agent_rounded,
                  size: 42,
                  color: _hubMutedText(context),
                ),
                const SizedBox(height: 8),
                const Text(
                  '¿Necesitas más ayuda?',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  'Abre el Centro Express para revisar avisos, chat y soporte.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _hubMutedText(context)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExpressCenterPage(service: service),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Contactar soporte'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Legal', style: TextStyle(fontWeight: FontWeight.w900)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Términos y condiciones'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showLegal(
              context,
              'Términos y condiciones',
              'El uso de Express implica respetar las reglas de seguridad, pagos, cancelaciones y conducta de la plataforma. La versión legal publicada por Express es la que prevalece.',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Privacidad'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showLegal(
              context,
              'Privacidad',
              'Express utiliza datos de cuenta, ubicación y servicio únicamente para operar viajes, seguridad, soporte y funciones de la plataforma según sus políticas aplicables.',
            ),
          ),
        ],
      ),
    );
  }

  void _showLegal(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final Widget child;

  const _HubCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _hubSurface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hubBorder(context)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );
}

class _HubInfo extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _HubInfo({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => _HubCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _hubBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    style: TextStyle(
                      color: _hubMutedText(context),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _HubError extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;

  const _HubError({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 44),
              const SizedBox(height: 10),
              const Text(
                'No pudimos cargar esta sección.',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                ExpressRuntimeChannel.userSafeError(
                  text,
                  fallback: 'Intenta nuevamente.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: _hubMutedText(context)),
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
      );
}

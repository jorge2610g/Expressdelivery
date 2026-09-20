import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';


const double baseDeliveryPrice = 1500;
const double pricePerKm = 800;

Future<LatLng> geocodeAddress(String address) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'format': 'jsonv2', 'limit': '1', 'q': address, 'countrycodes': 'cl',
  });
  final response = await http.get(uri, headers: {
    'Accept': 'application/json', 'Accept-Language': 'es-CL',
  });
  if (response.statusCode != 200) throw Exception('No se pudo buscar la dirección.');
  final data = jsonDecode(response.body) as List<dynamic>;
  if (data.isEmpty) throw Exception('No encontramos la dirección: ' + address);
  return LatLng(double.parse(data.first['lat'].toString()), double.parse(data.first['lon'].toString()));
}

Future<RouteResult> calculateRoute(String pickupAddress, String deliveryAddress) async {
  final pickup = await geocodeAddress(pickupAddress);
  final delivery = await geocodeAddress(deliveryAddress);
  final uri = Uri.parse(
    'https://router.project-osrm.org/route/v1/driving/' +
    pickup.longitude.toString() + ',' + pickup.latitude.toString() + ';' +
    delivery.longitude.toString() + ',' + delivery.latitude.toString() +
    '?overview=full&geometries=geojson',
  );
  final response = await http.get(uri);
  if (response.statusCode != 200) throw Exception('No se pudo calcular la ruta.');
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final routes = body['routes'] as List<dynamic>;
  if (routes.isEmpty) throw Exception('No encontramos una ruta.');
  final route = routes.first as Map<String, dynamic>;
  final distanceKm = (route['distance'] as num).toDouble() / 1000;
  final geometry = route['geometry']['coordinates'] as List<dynamic>;
  final points = geometry.map((p) {
    final coords = p as List<dynamic>;
    return LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
  }).toList();
  final price = ((baseDeliveryPrice + distanceKm * pricePerKm) / 100).round() * 100;
  return RouteResult(
    pickup: pickup, delivery: delivery, points: points,
    distanceKm: distanceKm, price: price.toDouble(),
  );
}

class RouteResult {
  final LatLng pickup;
  final LatLng delivery;
  final List<LatLng> points;
  final double distanceKm;
  final double price;
  const RouteResult({
    required this.pickup, required this.delivery, required this.points,
    required this.distanceKm, required this.price,
  });
}

const supabaseUrl = 'https://cdgemtkumzxlbhdgxlwn.supabase.co';
const supabasePublishableKey = 'sb_publishable_j7QozgTeNDz7jHch6W0XKg_VgSsvxXq';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const ExpressDeliveryApp());
}

final supabase = Supabase.instance.client;

class ExpressDeliveryApp extends StatelessWidget {
  const ExpressDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Express Delivery',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)), useMaterial3: true),
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: supabase.auth.onAuthStateChange,
    builder: (_, snapshot) {
      if (supabase.auth.currentSession == null) return const LoginPage();
      return const RoleGate();
    },
  );
}

class RoleGate extends StatefulWidget {
  const RoleGate({super.key});
  @override State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  String? role;
  bool loading = true;

  @override
  void initState() { super.initState(); _loadRole(); }

  Future<void> _loadRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final row = await supabase.from('profiles').select('role').eq('id', user.id).maybeSingle();
    if (mounted) setState(() { role = row?['role'] as String? ?? 'customer'; loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return role == 'driver' ? const DriverHomePage() : const CustomerHomePage();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  bool register = false, busy = false;

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      AuthResponse response;
      if (register) {
        response = await supabase.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          data: {'full_name': name.text.trim(), 'phone': phone.text.trim()},
        );
      } else {
        response = await supabase.auth.signInWithPassword(
          email: email.text.trim(), password: password.text,
        );
      }
      if (mounted && register && response.session == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revisa tu correo para confirmar la cuenta.')));
      }
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(children: [
            const Icon(Icons.local_shipping_rounded, size: 82),
            const SizedBox(height: 16),
            Text('Express Delivery', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 28),
            if (register) ...[
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre completo', prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone))),
              const SizedBox(height: 12),
            ],
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.email))),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña', prefixIcon: Icon(Icons.lock))),
            const SizedBox(height: 22),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: busy ? null : submit,
              child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(register ? 'Crear cuenta' : 'Ingresar'),
            )),
            TextButton(onPressed: busy ? null : () => setState(() => register = !register),
              child: Text(register ? 'Ya tengo una cuenta' : 'Crear una cuenta')),
          ]),
        ),
      ),
    ),
  );
}


const statusLabels = {
  'pending': 'Pendiente',
  'accepted': 'Aceptado',
  'picked_up': 'Retirado',
  'in_transit': 'En camino',
  'delivered': 'Entregado',
  'cancelled': 'Cancelado',
};

IconData statusIcon(String status) {
  switch (status) {
    case 'accepted': return Icons.check_circle_outline;
    case 'picked_up': return Icons.inventory_2_outlined;
    case 'in_transit': return Icons.local_shipping_outlined;
    case 'delivered': return Icons.done_all;
    case 'cancelled': return Icons.cancel_outlined;
    default: return Icons.schedule;
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(statusIcon(status), size: 17),
    label: Text(statusLabels[status] ?? status),
  );
}

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});
  @override State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  final pickup = TextEditingController();
  final delivery = TextEditingController();
  final notes = TextEditingController();
  bool busy = false;


  Future<void> calculateQuote() async {
    if (pickup.text.trim().isEmpty || delivery.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa ambas direcciones primero.')),
      );
      return;
    }
    setState(() => calculatingQuote = true);
    try {
      final result = await calculateRoute(pickup.text.trim(), delivery.text.trim());
      if (!mounted) return;
      setState(() {
        route = result;
        estimatedDistanceKm = result.distanceKm;
        estimatedPrice = result.price;
      });
      await showRouteMap(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo calcular la tarifa: ' + e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => calculatingQuote = false);
    }
  }

  Future<void> showRouteMap(RouteResult result) async {
    final bounds = LatLngBounds.fromPoints(result.points);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Row(
                children: [
                  const Icon(Icons.route),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ruta estimada · ' + result.distanceKm.toStringAsFixed(1) + ' km',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '\
    if (pickup.text.trim().isEmpty || delivery.text.trim().isEmpty) return;
    if (estimatedPrice == null) {
      await calculateQuote();
      if (estimatedPrice == null) return;
    }
    setState(() => busy = true);
    try {
      await supabase.from('orders').insert({
        'customer_id': supabase.auth.currentUser!.id,
        'pickup_address': pickup.text.trim(),
        'delivery_address': delivery.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'total': estimatedPrice,
      });
      pickup.clear(); delivery.clear(); notes.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido creado correctamente.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear el pedido: $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }


  Future<void> _showTracking(String orderId) async {
    try {
      final history = await supabase
          .from('order_status_history')
          .select('status,created_at')
          .eq('order_id', orderId)
          .order('created_at');
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seguimiento del pedido',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (history.isEmpty)
                  const Text('Todavía no hay cambios de estado.')
                else
                  ...history.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(statusIcon(item['status'] as String)),
                    title: Text(statusLabels[item['status']] ?? item['status']),
                    subtitle: Text(item['created_at'].toString()),
                  )),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar el seguimiento: $e')),
        );
      }
    }
  }

  Future<List<Map<String,dynamic>>> orders() async => await supabase.from('orders')
    .select('id,pickup_address,delivery_address,status,total,created_at')
    .eq('customer_id', supabase.auth.currentUser!.id)
    .order('created_at', ascending: false);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis pedidos'), actions: [
      IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout))
    ]),
    body: RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Solicitar entrega', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(controller: pickup, decoration: const InputDecoration(labelText: 'Dirección de retiro', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: delivery, decoration: const InputDecoration(labelText: 'Dirección de entrega', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : createOrder, icon: const Icon(Icons.add_box), label: const Text('Crear pedido')),
        const SizedBox(height: 28),
        Text('Historial', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String,dynamic>>>(
          future: orders(),
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Text('Error: ${snapshot.error}');
            final data = snapshot.data ?? [];
            if (data.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('Todavía no tienes pedidos.'));
            return Column(children: data.map((o) => Card(
              child: ListTile(
                onTap: () => _showTracking(o['id'] as String),
                leading: const Icon(Icons.local_shipping),
                title: Text('${o['pickup_address']} → ${o['delivery_address']}'),
                subtitle: Text('Estado: ${o['status']}'),
                trailing: Text('$ ${o['total']}'),
              ),
            )).toList());
          },
        ),
      ]),
    ),
  );
}


class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});
  @override State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  bool loading = true;
  bool saving = false;
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> drivers = [];
  final baseController = TextEditingController();
  final kmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  @override
  void dispose() {
    baseController.dispose();
    kmController.dispose();
    super.dispose();
  }

  Future<void> loadDashboard() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        supabase.from('orders').select('id,customer_id,driver_id,pickup_address,delivery_address,status,total,created_at').order('created_at', ascending: false),
        supabase.from('profiles').select('id,full_name,phone,role').eq('role', 'driver').order('full_name'),
        supabase.from('app_settings').select('base_price,price_per_km').eq('id', 1).maybeSingle(),
      ]);
      final settings = results[2] as Map<String, dynamic>?;
      if (settings != null) {
        baseController.text = settings['base_price'].toString();
        kmController.text = settings['price_per_km'].toString();
      }
      if (mounted) setState(() {
        orders = List<Map<String, dynamic>>.from(results[0] as List);
        drivers = List<Map<String, dynamic>>.from(results[1] as List);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ' + e.toString())));
      }
    }
  }

  Future<void> saveRates() async {
    final base = double.tryParse(baseController.text.replaceAll(',', '.'));
    final km = double.tryParse(kmController.text.replaceAll(',', '.'));
    if (base == null || km == null || base < 0 || km < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa valores válidos.')));
      return;
    }
    setState(() => saving = true);
    try {
      await supabase.from('app_settings').update({
        'base_price': base, 'price_per_km': km, 'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', 1);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarifas actualizadas.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: ' + e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> assignDriver(String orderId, String driverId) async {
    try {
      await supabase.from('orders').update({'driver_id': driverId, 'status': 'accepted'}).eq('id', orderId);
      await loadDashboard();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo asignar: ' + e.toString())));
    }
  }

  String driverName(String? id) {
    if (id == null) return 'Sin asignar';
    final match = drivers.where((d) => d['id'] == id);
    return match.isEmpty ? 'Repartidor' : (match.first['full_name'] ?? 'Repartidor').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: loadDashboard, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadDashboard,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Resumen', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _statCard('Pedidos', orders.length.toString(), Icons.receipt_long)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard('Pendientes', orders.where((o) => o['status'] == 'pending').length.toString(), Icons.schedule)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _statCard('En camino', orders.where((o) => o['status'] == 'in_transit').length.toString(), Icons.local_shipping)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard('Entregados', orders.where((o) => o['status'] == 'delivered').length.toString(), Icons.done_all)),
                  ]),
                  const SizedBox(height: 22),
                  Text('Tarifas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Card(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      TextField(controller: baseController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tarifa base (CLP)')),
                      const SizedBox(height: 10),
                      TextField(controller: kmController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio por km (CLP)')),
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: FilledButton.icon(
                        onPressed: saving ? null : saveRates,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(saving ? 'Guardando...' : 'Guardar tarifas'),
                      )),
                    ]),
                  )),
                  const SizedBox(height: 22),
                  Text('Pedidos', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (orders.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No hay pedidos.'))),
                  ...orders.map((o) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('Pedido ' + o['id'].toString().substring(0, 8), style: const TextStyle(fontWeight: FontWeight.bold))),
                          StatusChip(status: o['status'] as String),
                        ]),
                        const SizedBox(height: 8),
                        Text('Retiro: ' + o['pickup_address'].toString()),
                        Text('Entrega: ' + o['delivery_address'].toString()),
                        const SizedBox(height: 6),
                        Text('Total: 
  const DriverHomePage({super.key});
  @override State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  Future<List<Map<String,dynamic>>> orders() async => await supabase.from('orders')
    .select('id,pickup_address,delivery_address,status,total')
    .or('driver_id.eq.${supabase.auth.currentUser!.id},status.eq.pending')
    .order('created_at', ascending: false);

  Future<void> updateOrder(String id, String status) async {
    await supabase.from('orders').update({'status': status, 'driver_id': supabase.auth.currentUser!.id}).eq('id', id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Panel repartidor'), actions: [
      IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout))
    ]),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: orders(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        final data = snapshot.data ?? [];
        if (data.isEmpty) return const Center(child: Text('No hay pedidos disponibles.'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: data.length,
          itemBuilder: (_, i) {
            final o = data[i];
            final status = o['status'] as String;
            return Card(child: ListTile(
              title: Text('${o['pickup_address']} → ${o['delivery_address']}'),
              subtitle: StatusChip(status: status),
              trailing: status == 'pending'
                ? FilledButton(onPressed: () => updateOrder(o['id'], 'accepted'), child: const Text('Tomar'))
                : PopupMenuButton<String>(
                    onSelected: (s) => updateOrder(o['id'], s),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'picked_up', child: Text('Marcar retirado')),
                      PopupMenuItem(value: 'in_transit', child: Text('Marcar en camino')),
                      PopupMenuItem(value: 'delivered', child: Text('Marcar entregado')),
                    ],
                  ),
            ));
          },
        );
      },
    ),
  );
}
 + result.price.toStringAsFixed(0),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: result.pickup,
                  initialZoom: 12,
                  initialCameraFit: CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(40),
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.expressdelivery.app',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(points: result.points, strokeWidth: 5),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: result.pickup,
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.trip_origin, size: 34),
                      ),
                      Marker(
                        point: result.delivery,
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.location_on, size: 38),
                      ),
                    ],
                  ),
                  const RichAttributionWidget(
                    attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> createOrder() async {
    if (pickup.text.trim().isEmpty || delivery.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await supabase.from('orders').insert({
        'customer_id': supabase.auth.currentUser!.id,
        'pickup_address': pickup.text.trim(),
        'delivery_address': delivery.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      });
      pickup.clear(); delivery.clear(); notes.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido creado correctamente.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear el pedido: $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }


  Future<void> _showTracking(String orderId) async {
    try {
      final history = await supabase
          .from('order_status_history')
          .select('status,created_at')
          .eq('order_id', orderId)
          .order('created_at');
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seguimiento del pedido',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (history.isEmpty)
                  const Text('Todavía no hay cambios de estado.')
                else
                  ...history.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(statusIcon(item['status'] as String)),
                    title: Text(statusLabels[item['status']] ?? item['status']),
                    subtitle: Text(item['created_at'].toString()),
                  )),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar el seguimiento: $e')),
        );
      }
    }
  }

  Future<List<Map<String,dynamic>>> orders() async => await supabase.from('orders')
    .select('id,pickup_address,delivery_address,status,total,created_at')
    .eq('customer_id', supabase.auth.currentUser!.id)
    .order('created_at', ascending: false);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis pedidos'), actions: [
      IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout))
    ]),
    body: RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Solicitar entrega', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(controller: pickup, decoration: const InputDecoration(labelText: 'Dirección de retiro', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: delivery, decoration: const InputDecoration(labelText: 'Dirección de entrega', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : createOrder, icon: const Icon(Icons.add_box), label: const Text('Crear pedido')),
        const SizedBox(height: 28),
        Text('Historial', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String,dynamic>>>(
          future: orders(),
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Text('Error: ${snapshot.error}');
            final data = snapshot.data ?? [];
            if (data.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('Todavía no tienes pedidos.'));
            return Column(children: data.map((o) => Card(
              child: ListTile(
                onTap: () => _showTracking(o['id'] as String),
                leading: const Icon(Icons.local_shipping),
                title: Text('${o['pickup_address']} → ${o['delivery_address']}'),
                subtitle: Text('Estado: ${o['status']}'),
                trailing: Text('$ ${o['total']}'),
              ),
            )).toList());
          },
        ),
      ]),
    ),
  );
}

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});
  @override State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  Future<List<Map<String,dynamic>>> orders() async => await supabase.from('orders')
    .select('id,pickup_address,delivery_address,status,total')
    .or('driver_id.eq.${supabase.auth.currentUser!.id},status.eq.pending')
    .order('created_at', ascending: false);

  Future<void> updateOrder(String id, String status) async {
    await supabase.from('orders').update({'status': status, 'driver_id': supabase.auth.currentUser!.id}).eq('id', id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Panel repartidor'), actions: [
      IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout))
    ]),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: orders(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        final data = snapshot.data ?? [];
        if (data.isEmpty) return const Center(child: Text('No hay pedidos disponibles.'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: data.length,
          itemBuilder: (_, i) {
            final o = data[i];
            final status = o['status'] as String;
            return Card(child: ListTile(
              title: Text('${o['pickup_address']} → ${o['delivery_address']}'),
              subtitle: StatusChip(status: status),
              trailing: status == 'pending'
                ? FilledButton(onPressed: () => updateOrder(o['id'], 'accepted'), child: const Text('Tomar'))
                : PopupMenuButton<String>(
                    onSelected: (s) => updateOrder(o['id'], s),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'picked_up', child: Text('Marcar retirado')),
                      PopupMenuItem(value: 'in_transit', child: Text('Marcar en camino')),
                      PopupMenuItem(value: 'delivered', child: Text('Marcar entregado')),
                    ],
                  ),
            ));
          },
        );
      },
    ),
  );
}
 + o['total'].toString()),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: drivers.any((d) => d['id'] == o['driver_id']) ? o['driver_id'] as String : null,
                          decoration: const InputDecoration(labelText: 'Repartidor'),
                          items: drivers.map((d) => DropdownMenuItem<String>(
                            value: d['id'] as String,
                            child: Text((d['full_name'] ?? 'Repartidor').toString()),
                          )).toList(),
                          onChanged: (value) {
                            if (value != null) assignDriver(o['id'] as String, value);
                          },
                        ),
                        const SizedBox(height: 4),
                        Text('Asignado: ' + driverName(o['driver_id'] as String?)),
                      ]),
                    ),
                  )),
                ],
              ),
            ),
    );
  }

  Widget _statCard(String title, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Row(children: [
        Icon(icon),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title),
        ]),
      ]),
    ),
  );
}

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});
  @override State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  Future<List<Map<String,dynamic>>> orders() async => await supabase.from('orders')
    .select('id,pickup_address,delivery_address,status,total')
    .or('driver_id.eq.${supabase.auth.currentUser!.id},status.eq.pending')
    .order('created_at', ascending: false);

  Future<void> updateOrder(String id, String status) async {
    await supabase.from('orders').update({'status': status, 'driver_id': supabase.auth.currentUser!.id}).eq('id', id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Panel repartidor'), actions: [
      IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout))
    ]),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: orders(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        final data = snapshot.data ?? [];
        if (data.isEmpty) return const Center(child: Text('No hay pedidos disponibles.'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: data.length,
          itemBuilder: (_, i) {
            final o = data[i];
            final status = o['status'] as String;
            return Card(child: ListTile(
              title: Text('${o['pickup_address']} → ${o['delivery_address']}'),
              subtitle: StatusChip(status: status),
              trailing: status == 'pending'
                ? FilledButton(onPressed: () => updateOrder(o['id'], 'accepted'), child: const Text('Tomar'))
                : PopupMenuButton<String>(
                    onSelected: (s) => updateOrder(o['id'], s),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'picked_up', child: Text('Marcar retirado')),
                      PopupMenuItem(value: 'in_transit', child: Text('Marcar en camino')),
                      PopupMenuItem(value: 'delivered', child: Text('Marcar entregado')),
                    ],
                  ),
            ));
          },
        );
      },
    ),
  );
}
 + result.price.toStringAsFixed(0),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: result.pickup,
                  initialZoom: 12,
                  initialCameraFit: CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(40),
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.expressdelivery.app',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(points: result.points, strokeWidth: 5),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: result.pickup,
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.trip_origin, size: 34),
                      ),
                      Marker(
                        point: result.delivery,
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.location_on, size: 38),
                      ),
                    ],
                  ),
                  const RichAttributionWidget(
                    attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> createOrder() async {
    if (pickup.text.trim().isEmpty || delivery.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await supabase.from('orders').insert({
        'customer_id': supabase.auth.currentUser!.id,
        'pickup_address': pickup.text.trim(),
        'delivery_address': delivery.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      });
      pickup.clear(); delivery.clear(); notes.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido creado correctamente.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear el pedido: $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }


  Future<void> _showTracking(String orderId) async {
    try {
      final history = await supabase
          .from('order_status_history')
          .select('status,created_at')
          .eq('order_id', orderId)
          .order('created_at');
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seguimiento del pedido',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (history.isEmpty)
                  const Text('Todavía no hay cambios de estado.')
                else
                  ...history.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(statusIcon(item['status'] as String)),
                    title: Text(statusLabels[item['status']] ?? item['status']),
                    subtitle: Text(item['created_at'].toString()),
                  )),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar el seguimiento: $e')),
        );
      }
    }
  }

  Future<List<Map<String,dynamic>>> orders() async => await supabase.from('orders')
    .select('id,pickup_address,delivery_address,status,total,created_at')
    .eq('customer_id', supabase.auth.currentUser!.id)
    .order('created_at', ascending: false);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis pedidos'), actions: [
      IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout))
    ]),
    body: RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Solicitar entrega', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(controller: pickup, decoration: const InputDecoration(labelText: 'Dirección de retiro', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: delivery, decoration: const InputDecoration(labelText: 'Dirección de entrega', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : createOrder, icon: const Icon(Icons.add_box), label: const Text('Crear pedido')),
        const SizedBox(height: 28),
        Text('Historial', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String,dynamic>>>(
          future: orders(),
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Text('Error: ${snapshot.error}');
            final data = snapshot.data ?? [];
            if (data.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('Todavía no tienes pedidos.'));
            return Column(children: data.map((o) => Card(
              child: ListTile(
                onTap: () => _showTracking(o['id'] as String),
                leading: const Icon(Icons.local_shipping),
                title: Text('${o['pickup_address']} → ${o['delivery_address']}'),
                subtitle: Text('Estado: ${o['status']}'),
                trailing: Text('$ ${o['total']}'),
              ),
            )).toList());
          },
        ),
      ]),
    ),
  );
}

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});
  @override State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  Future<List<Map<String,dynamic>>> orders() async => await supabase.from('orders')
    .select('id,pickup_address,delivery_address,status,total')
    .or('driver_id.eq.${supabase.auth.currentUser!.id},status.eq.pending')
    .order('created_at', ascending: false);

  Future<void> updateOrder(String id, String status) async {
    await supabase.from('orders').update({'status': status, 'driver_id': supabase.auth.currentUser!.id}).eq('id', id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Panel repartidor'), actions: [
      IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout))
    ]),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: orders(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        final data = snapshot.data ?? [];
        if (data.isEmpty) return const Center(child: Text('No hay pedidos disponibles.'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: data.length,
          itemBuilder: (_, i) {
            final o = data[i];
            final status = o['status'] as String;
            return Card(child: ListTile(
              title: Text('${o['pickup_address']} → ${o['delivery_address']}'),
              subtitle: StatusChip(status: status),
              trailing: status == 'pending'
                ? FilledButton(onPressed: () => updateOrder(o['id'], 'accepted'), child: const Text('Tomar'))
                : PopupMenuButton<String>(
                    onSelected: (s) => updateOrder(o['id'], s),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'picked_up', child: Text('Marcar retirado')),
                      PopupMenuItem(value: 'in_transit', child: Text('Marcar en camino')),
                      PopupMenuItem(value: 'delivered', child: Text('Marcar entregado')),
                    ],
                  ),
            ));
          },
        );
      },
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          emailRedirectTo: 'https://jorge2610g.github.io/Expressdelivery/',
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
                trailing: Text('\$ ${o['total']}'),
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

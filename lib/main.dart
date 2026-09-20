import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_theme.dart';
import 'core/supabase_client.dart';
import 'models/order_model.dart';
import 'services/auth_service.dart';
import 'services/order_service.dart';
import 'widgets/status_chip.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(const ExpressDeliveryApp());
}

class ExpressDeliveryApp extends StatelessWidget {
  const ExpressDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Express Delivery',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
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
    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
      final row = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (mounted) {
        setState(() {
          role = row?['role'] as String? ?? 'customer';
          loading = false;
        });
      }
    } catch (_) {
      // Never leave the user on an infinite loading screen if the profile
      // request fails or the network is slow. New accounts default to customer.
      if (mounted) {
        setState(() {
          role = 'customer';
          loading = false;
        });
      }
    }
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
        // Fallback for projects that still require email confirmation.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cuenta creada. Ya puedes iniciar sesión.')),
        );
        setState(() => register = false);
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


class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});
  @override State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  final pickup = TextEditingController();
  final delivery = TextEditingController();
  final notes = TextEditingController();
  final orderService = OrderService();
  bool busy = false;

  Future<void> createOrder() async {
    FocusScope.of(context).unfocus();
    if (pickup.text.trim().isEmpty || delivery.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa la dirección de retiro y de entrega.')),
      );
      return;
    }
    setState(() => busy = true);
    try {
      await orderService.createOrder(
        pickupAddress: pickup.text.trim(),
        deliveryAddress: delivery.text.trim(),
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
      pickup.clear(); delivery.clear(); notes.clear();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido creado correctamente.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear el pedido: $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }


  Future<void> _showTracking(String orderId) async {
    try {
      final history = await orderService.tracking(orderId);
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

  Future<List<OrderModel>> orders() => orderService.customerOrders();

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
        FutureBuilder<List<OrderModel>>(
          future: orders(),
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Text('Error: ${snapshot.error}');
            final data = snapshot.data ?? [];
            if (data.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('Todavía no tienes pedidos.'));
            return Column(
              children: data.map((o) => Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _showTracking(o.id),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                statusIcon(o.status),
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pedido #${o.id.length > 8 ? o.id.substring(0, 8).toUpperCase() : o.id.toUpperCase()}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (o.createdAt != null)
                                    Text(
                                      _formatOrderDate(o.createdAt!),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            StatusChip(status: o.status),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _AddressRow(
                          icon: Icons.radio_button_checked,
                          label: 'Retiro',
                          address: o.pickupAddress,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 11),
                          child: Container(
                            width: 2,
                            height: 18,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        _AddressRow(
                          icon: Icons.location_on,
                          label: 'Entrega',
                          address: o.deliveryAddress,
                        ),
                        const Divider(height: 28),
                        Row(
                          children: [
                            const Icon(Icons.touch_app_outlined, size: 18),
                            const SizedBox(width: 6),
                            const Expanded(child: Text('Toca para ver el seguimiento')),
                            if (o.total != null && o.total! > 0)
                              Text(
                                '\$ ${o.total}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )).toList(),
            );
          },
        ),
      ]),
    ),
  );
}


String _formatOrderDate(DateTime date) {
  final local = date.toLocal();
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} · $hour:$minute';
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String address;

  const _AddressRow({
    required this.icon,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 2),
            Text(address, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    ],
  );
}

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});
  @override State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  final orderService = OrderService();

  Future<List<OrderModel>> orders() => orderService.driverOrders();

  Future<void> updateOrder(String id, String status) async {
    try {
      await orderService.updateOrder(id, status);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pedido actualizado: ${statusLabels[status] ?? status}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar el pedido: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Panel repartidor'), actions: [
      IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout))
    ]),
    body: FutureBuilder<List<OrderModel>>(
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
            final status = o.status;
            return Card(child: ListTile(
              title: Text('${o.pickupAddress} → ${o.deliveryAddress}'),
              subtitle: StatusChip(status: status),
              trailing: status == 'pending'
                ? FilledButton(onPressed: () => updateOrder(o.id, 'accepted'), child: const Text('Tomar'))
                : PopupMenuButton<String>(
                    onSelected: (s) => updateOrder(o.id, s),
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

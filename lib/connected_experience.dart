import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';
import 'location_picker.dart';
import 'location_service.dart';
import 'services/express_service.dart';
import 'service_tracking.dart';
import 'video_style_home.dart';

const _blue = Color(0xFF0B57D0);
const _blueDark = Color(0xFF073B8C);
const _yellow = Color(0xFFFFC928);
const _bg = Color(0xFFF5F7FB);
const _muted = Color(0xFF667085);

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

class ConnectedExperience extends StatefulWidget {
  final VoidCallback onExit;
  const ConnectedExperience({super.key, required this.onExit});

  @override
  State<ConnectedExperience> createState() => _ConnectedExperienceState();
}

class _ConnectedExperienceState extends State<ConnectedExperience> {
  final service = ExpressService();
  bool loading = true;
  String mode = 'passenger';
  String? error;
  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final userId = supabase.auth.currentUser?.id ?? 'unknown';
    _realtimeChannel = supabase
        .channel('express-core-' + userId)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_requests',
          callback: (_) => _queueRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_offers',
          callback: (_) => _queueRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          callback: (_) => _queueRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'delivery_requests',
          callback: (_) => _queueRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _queueRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_messages',
          callback: (_) => _queueRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_profiles',
          callback: (_) => _queueRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ratings',
          callback: (_) => _queueRealtimeRefresh(),
        )
        .subscribe();
  }

  void _queueRealtimeRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    try {
      final user = await service.myUser();
      if (!mounted) return;
      setState(() {
        mode = user?['active_mode']?.toString() ?? 'passenger';
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _switchMode(String value) async {
    try {
      if (value == 'driver') {
        await service.ensureDriverProfile();
      }
      await service.setActiveMode(value);
      if (!mounted) return;
      setState(() => mode = value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar de modo: $e')),
      );
    }
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _blue),
      scaffoldBackgroundColor: _bg,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
        ),
      ),
    );

    if (loading) {
      return Theme(
        data: theme,
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (error != null) {
      return Theme(
        data: theme,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 50),
                  const SizedBox(height: 12),
                  const Text('No se pudo cargar tu cuenta.'),
                  const SizedBox(height: 8),
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('Reintentar')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Theme(
      data: theme,
      child: mode == 'driver'
          ? _DriverShell(
              service: service,
              onSwitchMode: () => _switchMode('passenger'),
              onExit: widget.onExit,
            )
          : _CustomerShell(
              service: service,
              onSwitchMode: () => _switchMode('driver'),
              onExit: widget.onExit,
            ),
    );
  }
}

class _CustomerShell extends StatefulWidget {
  final ExpressService service;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;

  const _CustomerShell({
    required this.service,
    required this.onSwitchMode,
    required this.onExit,
  });

  @override
  State<_CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<_CustomerShell> {
  int index = 0;
  int revision = 0;

  void refreshAll() => setState(() => revision++);

  @override
  Widget build(BuildContext context) {
    final pages = [
      PassengerMapHome(
        service: widget.service,
        onChanged: refreshAll,
        onSwitchMode: widget.onSwitchMode,
        onHistory: () => setState(() => index = 1),
        onPayments: () => setState(() => index = 2),
        onProfile: () => setState(() => index = 3),
        onSavedPlaces: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SavedAddressesPage(service: widget.service),
          ),
        ),
        onSafety: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SafetyPage(service: widget.service),
          ),
        ),
      ),
      _CustomerActivity(service: widget.service, revision: revision),
      _PaymentsPage(service: widget.service, revision: revision),
      _ProfilePage(
        service: widget.service,
        driver: false,
        onSwitchMode: widget.onSwitchMode,
        onExit: widget.onExit,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Historial'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Pagos'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _CustomerHome extends StatelessWidget {
  final ExpressService service;
  final VoidCallback onChanged;
  const _CustomerHome({required this.service, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => onChanged(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: [
            const _TopBrand(role: 'Cliente'),
            const SizedBox(height: 22),
            const Text('¿Qué necesitas hoy?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Viajes y envíos conectados a tu cuenta real.', style: TextStyle(color: _muted)),
            const SizedBox(height: 22),
            _ServiceCard(
              icon: Icons.local_taxi_rounded,
              title: 'Pedir un viaje',
              subtitle: 'Solicita un conductor y recibe ofertas.',
              button: 'Solicitar viaje',
              onTap: () async {
                final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _CreateRidePage(service: service)));
                if (changed == true) onChanged();
              },
            ),
            const SizedBox(height: 14),
            _ServiceCard(
              icon: Icons.local_shipping_rounded,
              title: 'Enviar un delivery',
              subtitle: 'Documento, paquete, compra u otro envío.',
              button: 'Crear envío',
              dark: true,
              onTap: () async {
                final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _CreateDeliveryPage(service: service)));
                if (changed == true) onChanged();
              },
            ),
            const SizedBox(height: 24),
            const _InfoCard(
              icon: Icons.verified_user_outlined,
              title: 'Datos reales',
              text: 'Las solicitudes creadas aquí se guardan en Supabase y pueden ser vistas por conductores aprobados.',
            ),
          ],
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>?> _chooseSavedAddress(
  BuildContext context,
  ExpressService service,
) async {
  final rows = await service.savedAddresses();
  if (!context.mounted) return null;

  if (rows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Todavía no tienes direcciones guardadas.'),
      ),
    );
    return null;
  }

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          const Text(
            'Direcciones guardadas',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.location_on_outlined),
              ),
              title: Text(row['label']?.toString() ?? 'Dirección'),
              subtitle: Text(row['address']?.toString() ?? ''),
              onTap: () => Navigator.pop(sheetContext, row),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CreateRidePage extends StatefulWidget {
  final ExpressService service;
  const _CreateRidePage({required this.service});

  @override
  State<_CreateRidePage> createState() => _CreateRidePageState();
}

class _CreateRidePageState extends State<_CreateRidePage> {
  final pickup = TextEditingController();
  final destination = TextEditingController();
  final fare = TextEditingController(text: '5');
  String category = 'economy';
  String payment = 'cash';
  bool busy = false;
  double? pickupLatitude;
  double? pickupLongitude;
  double? destinationLatitude;
  double? destinationLongitude;

  Future<void> _pickLocation({required bool pickupPoint}) async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: pickupPoint ? 'Seleccionar origen' : 'Seleccionar destino',
          initialLabel: pickupPoint ? pickup.text : destination.text,
          initialLatitude:
              pickupPoint ? pickupLatitude : destinationLatitude,
          initialLongitude:
              pickupPoint ? pickupLongitude : destinationLongitude,
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      if (pickupPoint) {
        pickup.text = result.label;
        pickupLatitude = result.latitude;
        pickupLongitude = result.longitude;
      } else {
        destination.text = result.label;
        destinationLatitude = result.latitude;
        destinationLongitude = result.longitude;
      }
    });
  }

  Future<void> _useSavedAddress({required bool pickupPoint}) async {
    final row = await _chooseSavedAddress(context, widget.service);
    if (row == null || !mounted) return;

    setState(() {
      final address = row['address']?.toString() ?? '';
      final latitude = _asDouble(row['latitude']);
      final longitude = _asDouble(row['longitude']);
      if (pickupPoint) {
        pickup.text = address;
        pickupLatitude = latitude;
        pickupLongitude = longitude;
      } else {
        destination.text = address;
        destinationLatitude = latitude;
        destinationLongitude = longitude;
      }
    });
  }

  @override
  void dispose() {
    pickup.dispose();
    destination.dispose();
    fare.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final amount = num.tryParse(fare.text.replaceAll(',', '.'));
    if (pickup.text.trim().isEmpty || destination.text.trim().isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa origen, destino y tarifa.')));
      return;
    }
    setState(() => busy = true);
    try {
      await widget.service.createRideRequest(
        category: category,
        pickupAddress: pickup.text.trim(),
        destinationAddress: destination.text.trim(),
        proposedFare: amount,
        paymentMethod: payment,
        pickupLatitude: pickupLatitude,
        pickupLongitude: pickupLongitude,
        destinationLatitude: destinationLatitude,
        destinationLongitude: destinationLongitude,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear el viaje: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar viaje')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: pickup,
            decoration: InputDecoration(
              labelText: 'Punto de partida',
              prefixIcon: const Icon(Icons.my_location_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Direcciones guardadas',
                    onPressed: () => _useSavedAddress(pickupPoint: true),
                    icon: const Icon(Icons.bookmark_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Elegir en mapa',
                    onPressed: () => _pickLocation(pickupPoint: true),
                    icon: Icon(
                      pickupLatitude == null
                          ? Icons.map_outlined
                          : Icons.check_circle_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: destination,
            decoration: InputDecoration(
              labelText: 'Destino',
              prefixIcon: const Icon(Icons.location_on_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Direcciones guardadas',
                    onPressed: () => _useSavedAddress(pickupPoint: false),
                    icon: const Icon(Icons.bookmark_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Elegir en mapa',
                    onPressed: () => _pickLocation(pickupPoint: false),
                    icon: Icon(
                      destinationLatitude == null
                          ? Icons.map_outlined
                          : Icons.check_circle_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Tipo de vehículo'),
            items: const [
              DropdownMenuItem(value: 'economy', child: Text('Express')),
              DropdownMenuItem(value: 'comfort', child: Text('Comfort')),
              DropdownMenuItem(value: 'xl', child: Text('XL')),
              DropdownMenuItem(value: 'motorcycle', child: Text('Moto')),
            ],
            onChanged: (v) => setState(() => category = v ?? 'economy'),
          ),
          const SizedBox(height: 12),
          TextField(controller: fare, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Tarifa propuesta (Bs)', prefixIcon: Icon(Icons.payments_outlined))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: payment,
            decoration: const InputDecoration(labelText: 'Forma de pago'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
              DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
              DropdownMenuItem(value: 'wallet', child: Text('Billetera Express')),
            ],
            onChanged: (v) => setState(() => payment = v ?? 'cash'),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: busy ? null : submit,
            icon: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.local_taxi_rounded),
            label: const Text('Buscar conductor'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          ),
        ],
      ),
    );
  }
}

class _CreateDeliveryPage extends StatefulWidget {
  final ExpressService service;
  const _CreateDeliveryPage({required this.service});

  @override
  State<_CreateDeliveryPage> createState() => _CreateDeliveryPageState();
}

class _CreateDeliveryPageState extends State<_CreateDeliveryPage> {
  final pickup = TextEditingController();
  final dropoff = TextEditingController();
  final details = TextEditingController();
  final fare = TextEditingController(text: '8');
  String packageType = 'package';
  String payment = 'cash';
  bool busy = false;
  double? pickupLatitude;
  double? pickupLongitude;
  double? dropoffLatitude;
  double? dropoffLongitude;

  Future<void> _pickLocation({required bool pickupPoint}) async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: pickupPoint
              ? 'Seleccionar recogida'
              : 'Seleccionar entrega',
          initialLabel: pickupPoint ? pickup.text : dropoff.text,
          initialLatitude: pickupPoint ? pickupLatitude : dropoffLatitude,
          initialLongitude:
              pickupPoint ? pickupLongitude : dropoffLongitude,
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      if (pickupPoint) {
        pickup.text = result.label;
        pickupLatitude = result.latitude;
        pickupLongitude = result.longitude;
      } else {
        dropoff.text = result.label;
        dropoffLatitude = result.latitude;
        dropoffLongitude = result.longitude;
      }
    });
  }

  Future<void> _useSavedAddress({required bool pickupPoint}) async {
    final row = await _chooseSavedAddress(context, widget.service);
    if (row == null || !mounted) return;

    setState(() {
      final address = row['address']?.toString() ?? '';
      final latitude = _asDouble(row['latitude']);
      final longitude = _asDouble(row['longitude']);
      if (pickupPoint) {
        pickup.text = address;
        pickupLatitude = latitude;
        pickupLongitude = longitude;
      } else {
        dropoff.text = address;
        dropoffLatitude = latitude;
        dropoffLongitude = longitude;
      }
    });
  }

  @override
  void dispose() {
    pickup.dispose();
    dropoff.dispose();
    details.dispose();
    fare.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final amount = num.tryParse(fare.text.replaceAll(',', '.'));
    if (pickup.text.trim().isEmpty || dropoff.text.trim().isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa recogida, entrega y tarifa.')));
      return;
    }
    setState(() => busy = true);
    try {
      await widget.service.createDelivery(
        packageType: packageType,
        pickupAddress: pickup.text.trim(),
        dropoffAddress: dropoff.text.trim(),
        proposedFare: amount,
        paymentMethod: payment,
        details: details.text.trim().isEmpty ? null : details.text.trim(),
        pickupLatitude: pickupLatitude,
        pickupLongitude: pickupLongitude,
        dropoffLatitude: dropoffLatitude,
        dropoffLongitude: dropoffLongitude,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear el delivery: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo delivery')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: pickup,
            decoration: InputDecoration(
              labelText: 'Dirección de recogida',
              prefixIcon: const Icon(Icons.trip_origin_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Direcciones guardadas',
                    onPressed: () => _useSavedAddress(pickupPoint: true),
                    icon: const Icon(Icons.bookmark_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Elegir en mapa',
                    onPressed: () => _pickLocation(pickupPoint: true),
                    icon: Icon(
                      pickupLatitude == null
                          ? Icons.map_outlined
                          : Icons.check_circle_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: dropoff,
            decoration: InputDecoration(
              labelText: 'Dirección de entrega',
              prefixIcon: const Icon(Icons.location_on_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Direcciones guardadas',
                    onPressed: () => _useSavedAddress(pickupPoint: false),
                    icon: const Icon(Icons.bookmark_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Elegir en mapa',
                    onPressed: () => _pickLocation(pickupPoint: false),
                    icon: Icon(
                      dropoffLatitude == null
                          ? Icons.map_outlined
                          : Icons.check_circle_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: packageType,
            decoration: const InputDecoration(labelText: 'Tipo de envío'),
            items: const [
              DropdownMenuItem(value: 'document', child: Text('Documento')),
              DropdownMenuItem(value: 'package', child: Text('Paquete')),
              DropdownMenuItem(value: 'purchase', child: Text('Compra')),
              DropdownMenuItem(value: 'other', child: Text('Otro')),
            ],
            onChanged: (v) => setState(() => packageType = v ?? 'package'),
          ),
          const SizedBox(height: 12),
          TextField(controller: details, maxLines: 2, decoration: const InputDecoration(labelText: 'Detalles del envío')),
          const SizedBox(height: 12),
          TextField(controller: fare, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Tarifa propuesta (Bs)', prefixIcon: Icon(Icons.payments_outlined))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: payment,
            decoration: const InputDecoration(labelText: 'Forma de pago'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
              DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
              DropdownMenuItem(value: 'wallet', child: Text('Billetera Express')),
            ],
            onChanged: (v) => setState(() => payment = v ?? 'cash'),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: busy ? null : submit,
            icon: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.local_shipping_rounded),
            label: const Text('Buscar repartidor'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          ),
        ],
      ),
    );
  }
}

class _CustomerActivity extends StatefulWidget {
  final ExpressService service;
  final int revision;
  const _CustomerActivity({
    required this.service,
    required this.revision,
  });

  @override
  State<_CustomerActivity> createState() => _CustomerActivityState();
}

class _CustomerActivityState extends State<_CustomerActivity> {
  int refresh = 0;
  String filter = 'all';

  Future<_ActivityBundle> load() async {
    final rides = await widget.service.myRideRequests();
    final trips = await widget.service.myTrips();
    final deliveries = await widget.service.myDeliveries();

    final tripRequestIds = trips
        .map((trip) => trip['ride_request_id']?.toString())
        .whereType<String>()
        .toSet();

    final standaloneRides = rides
        .where(
          (ride) => !tripRequestIds.contains(ride['id']?.toString()),
        )
        .toList();

    return _ActivityBundle(
      standaloneRides,
      trips,
      deliveries,
    );
  }

  bool _scheduled(Map<String, dynamic> ride) {
    final raw = ride['scheduled_for']?.toString();
    if (raw == null || raw.isEmpty) return false;
    final date = DateTime.tryParse(raw)?.toLocal();
    return date != null && date.isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_ActivityBundle>(
        key: ValueKey('${widget.revision}-$refresh'),
        future: load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.all(18),
              children: const [
                _TopBrand(role: 'Historial'),
                SizedBox(height: 20),
                Text(
                  'Mis servicios',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 14),
                LinearProgressIndicator(),
                SizedBox(height: 14),
                _InfoCard(
                  icon: Icons.sync_rounded,
                  title: 'Actualizando servicios',
                  text: 'Estamos sincronizando tus viajes y delivery.',
                ),
              ],
            );
          }
          if (snapshot.hasError) {
            return _ErrorView(
              error: snapshot.error,
              onRetry: () => setState(() => refresh++),
            );
          }

          final data = snapshot.data!;
          final scheduledRides =
              data.rides.where(_scheduled).toList();
          final regularRides =
              data.rides.where((ride) => !_scheduled(ride)).toList();

          final showRides = filter == 'all' || filter == 'rides';
          final showDelivery = filter == 'all' || filter == 'delivery';
          final showScheduled = filter == 'scheduled';

          final visibleCount = showScheduled
              ? scheduledRides.length
              : (showRides ? regularRides.length + data.trips.length : 0) +
                  (showDelivery ? data.deliveries.length : 0);

          return RefreshIndicator(
            onRefresh: () async => setState(() => refresh++),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Historial'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mis servicios',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        visibleCount.toString(),
                        style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ActivityFilterChip(
                        label: 'Todos',
                        icon: Icons.apps_rounded,
                        selected: filter == 'all',
                        onTap: () => setState(() => filter = 'all'),
                      ),
                      _ActivityFilterChip(
                        label: 'Viajes',
                        icon: Icons.local_taxi_rounded,
                        selected: filter == 'rides',
                        onTap: () => setState(() => filter = 'rides'),
                      ),
                      _ActivityFilterChip(
                        label: 'Delivery',
                        icon: Icons.local_shipping_rounded,
                        selected: filter == 'delivery',
                        onTap: () => setState(() => filter = 'delivery'),
                      ),
                      _ActivityFilterChip(
                        label: 'Programados',
                        icon: Icons.event_outlined,
                        selected: filter == 'scheduled',
                        onTap: () => setState(() => filter = 'scheduled'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (visibleCount == 0)
                  _InfoCard(
                    icon: showScheduled
                        ? Icons.event_busy_outlined
                        : Icons.inbox_outlined,
                    title: showScheduled
                        ? 'Sin viajes programados'
                        : 'Sin actividad',
                    text: showScheduled
                        ? 'Cuando programes un viaje futuro aparecerá aquí.'
                        : 'Tus viajes y delivery aparecerán aquí.',
                  )
                else if (showScheduled)
                  ...scheduledRides.map(
                    (ride) => _RideRequestCard(
                      service: widget.service,
                      ride: ride,
                      onChanged: () => setState(() => refresh++),
                    ),
                  )
                else ...[
                  if (showRides) ...[
                    ...regularRides.map(
                      (ride) => _RideRequestCard(
                        service: widget.service,
                        ride: ride,
                        onChanged: () => setState(() => refresh++),
                      ),
                    ),
                    ...data.trips.map(
                      (trip) => _TripCard(
                        service: widget.service,
                        trip: trip,
                        onChanged: () => setState(() => refresh++),
                      ),
                    ),
                  ],
                  if (showDelivery)
                    ...data.deliveries.map(
                      (delivery) => _DeliveryCard(
                        service: widget.service,
                        delivery: delivery,
                        onChanged: () => setState(() => refresh++),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActivityFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ActivityFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: Icon(
          icon,
          size: 17,
          color: selected ? _blue : _muted,
        ),
        label: Text(label),
        selectedColor: const Color(0xFFEAF2FF),
        side: BorderSide(
          color: selected ? _blue : const Color(0xFFE4E7EC),
        ),
        labelStyle: TextStyle(
          color: selected ? _blue : _muted,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

Future<void> _showServiceDetails(
  BuildContext context,
  ExpressService service, {
  required String type,
  required Map<String, dynamic> data,
}) async {
  Map<String, dynamic> route = data;
  Map<String, dynamic>? counterpart;
  Map<String, dynamic>? driverProfile;

  if (type == 'trip') {
    final raw = data['ride_requests'];
    if (raw is Map) route = Map<String, dynamic>.from(raw);
    final driverId = data['driver_id']?.toString();
    if (driverId != null) {
      counterpart = await service.userById(driverId);
      driverProfile = await service.driverProfileById(driverId);
    }
  } else if (type == 'delivery') {
    final driverId = data['courier_id']?.toString();
    if (driverId != null) {
      counterpart = await service.userById(driverId);
      driverProfile = await service.driverProfileById(driverId);
    }
  }

  if (!context.mounted) return;

  String statusLabel(String? value) {
    switch (value) {
      case 'searching':
        return 'Buscando conductor';
      case 'offers_received':
        return 'Ofertas recibidas';
      case 'driver_assigned':
        return 'Conductor asignado';
      case 'driver_arriving':
        return 'Conductor en camino';
      case 'driver_waiting':
        return 'Conductor esperando';
      case 'in_progress':
        return 'En viaje';
      case 'completed':
        return 'Completado';
      case 'accepted':
        return 'Repartidor asignado';
      case 'picked_up':
        return 'Paquete recogido';
      case 'in_transit':
        return 'En camino';
      case 'delivered':
        return 'Entregado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return value ?? 'Sin estado';
    }
  }

  String paymentLabel(String? value) {
    switch (value) {
      case 'cash':
        return 'Efectivo';
      case 'wallet':
        return 'Billetera Express';
      case 'card':
        return 'Tarjeta';
      default:
        return value ?? 'No definido';
    }
  }

  String formatDate(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (parsed == null) return '—';
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return day +
        '/' +
        month +
        '/' +
        parsed.year.toString() +
        ' · ' +
        hour +
        ':' +
        minute;
  }

  final isDelivery = type == 'delivery';
  final isTrip = type == 'trip';
  final origin =
      isDelivery ? data['pickup_address'] : route['pickup_address'];
  final destination =
      isDelivery ? data['dropoff_address'] : route['destination_address'];
  final fare = isTrip
      ? data['final_fare'] ?? route['proposed_fare']
      : data['proposed_fare'];
  final payment =
      isTrip ? route['payment_method'] : data['payment_method'];
  final scheduled =
      isTrip ? route['scheduled_for'] : data['scheduled_for'];

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFFEAF2FF),
                  child: Icon(
                    isDelivery
                        ? Icons.local_shipping_rounded
                        : Icons.local_taxi_rounded,
                    color: _blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDelivery
                            ? 'Detalle del delivery'
                            : isTrip
                                ? 'Detalle del viaje'
                                : 'Detalle de la solicitud',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        statusLabel(data['status']?.toString()),
                        style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _ServiceDetailRow(
              icon: Icons.trip_origin_rounded,
              label: 'Origen',
              value: origin?.toString() ?? '—',
            ),
            _ServiceDetailRow(
              icon: Icons.location_on_rounded,
              label: 'Destino',
              value: destination?.toString() ?? '—',
            ),
            _ServiceDetailRow(
              icon: Icons.payments_outlined,
              label: 'Tarifa',
              value: 'Bs ' + (fare?.toString() ?? '—'),
            ),
            _ServiceDetailRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Pago',
              value: paymentLabel(payment?.toString()),
            ),
            if (!isDelivery)
              _ServiceDetailRow(
                icon: Icons.directions_car_outlined,
                label: 'Servicio',
                value: route['category']?.toString() ?? 'Express',
              ),
            if (scheduled != null)
              _ServiceDetailRow(
                icon: Icons.event_outlined,
                label: 'Programado',
                value: formatDate(scheduled),
              ),
            _ServiceDetailRow(
              icon: Icons.schedule_rounded,
              label: 'Creado',
              value: formatDate(data['created_at']),
            ),
            if (counterpart != null) ...[
              const Divider(height: 30),
              const Text(
                'Persona asignada',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              _ServiceDetailRow(
                icon: Icons.person_outline_rounded,
                label: isDelivery ? 'Repartidor' : 'Conductor',
                value:
                    counterpart['full_name']?.toString().trim().isNotEmpty ==
                            true
                        ? counterpart['full_name'].toString()
                        : 'Usuario Express',
              ),
              if (driverProfile?['vehicle_summary'] != null)
                _ServiceDetailRow(
                  icon: Icons.directions_car_filled_outlined,
                  label: 'Vehículo',
                  value: driverProfile!['vehicle_summary'].toString(),
                ),
              if (driverProfile?['rating'] != null)
                _ServiceDetailRow(
                  icon: Icons.star_outline_rounded,
                  label: 'Calificación',
                  value: driverProfile!['rating'].toString(),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ServiceDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ServiceDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _blue, size: 21),
          const SizedBox(width: 11),
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askCancellationReason(
  BuildContext context,
  String serviceName,
) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Cancelar $serviceName'),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Motivo (opcional)',
          hintText: 'Ej. Cambié de planes',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Confirmar cancelación'),
        ),
      ],
    ),
  );
  final reason = confirmed == true ? controller.text.trim() : null;
  controller.dispose();
  return reason;
}

class _RideRequestCard extends StatelessWidget {
  final ExpressService service;
  final Map<String, dynamic> ride;
  final VoidCallback onChanged;
  const _RideRequestCard({required this.service, required this.ride, required this.onChanged});

  Future<void> offers(BuildContext context) async {
    try {
      final list = await service.offersForRide(ride['id'].toString());
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ofertas de conductores', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Todavía no hay ofertas.'))
                else
                  ...list.map((offer) {
                    final driver = offer['driver_profiles'];
                    final info = driver is Map ? Map<String, dynamic>.from(driver) : <String, dynamic>{};
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                        title: Text('Bs ${offer['proposed_fare']} · ${offer['eta_minutes'] ?? '?'} min'),
                        subtitle: Text('★ ${info['rating'] ?? '5'} · ${info['vehicle_summary'] ?? 'Vehículo por confirmar'}'),
                        trailing: offer['status'] == 'pending'
                            ? FilledButton(
                                onPressed: () async {
                                  try {
                                    await service.selectRideOffer(offer['id'].toString());
                                    if (!sheetContext.mounted) return;
                                    Navigator.pop(sheetContext);
                                    onChanged();
                                  } catch (e) {
                                    if (!sheetContext.mounted) return;
                                    ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text('No se pudo seleccionar: $e')));
                                  }
                                },
                                child: const Text('Elegir'),
                              )
                            : Text(offer['status'].toString()),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudieron cargar las ofertas: $e')));
    }
  }

  Future<void> cancel(BuildContext context) async {
    final reason = await _askCancellationReason(context, 'solicitud');
    if (reason == null || !context.mounted) return;
    try {
      await service.cancelRideRequest(
        ride['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud cancelada.')),
      );
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cancellable = ['searching', 'offers_received'].contains(ride['status']);
    return _RecordCard(
      icon: Icons.local_taxi_rounded,
      title: '${ride['pickup_address']} → ${ride['destination_address']}',
      subtitle: 'Viaje · ${ride['status']} · Bs ${ride['proposed_fare']}',
      onTap: () => _showServiceDetails(
        context,
        service,
        type: 'ride_request',
        data: ride,
      ),
      action: cancellable
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => offers(context),
                  child: const Text('Ofertas'),
                ),
                IconButton(
                  tooltip: 'Cancelar solicitud',
                  onPressed: () => cancel(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            )
          : null,
    );
  }
}

class _TripCard extends StatelessWidget {
  final ExpressService service;
  final Map<String, dynamic> trip;
  final VoidCallback onChanged;
  const _TripCard({
    required this.service,
    required this.trip,
    required this.onChanged,
  });

  Future<void> cancel(BuildContext context) async {
    final reason = await _askCancellationReason(context, 'viaje');
    if (reason == null || !context.mounted) return;
    try {
      await service.cancelTrip(
        trip['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viaje cancelado.')),
      );
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = trip['ride_requests'];
    final route = ride is Map
        ? '${ride['pickup_address'] ?? 'Origen'} → ${ride['destination_address'] ?? 'Destino'}'
        : 'Viaje';
    final status = trip['status']?.toString();
    final cancellable = trip['passenger_id'] == service.userId &&
        ['driver_assigned', 'driver_arriving', 'driver_waiting'].contains(status);
    final driverId = trip['driver_id']?.toString();
    return _RecordCard(
      icon: Icons.route_rounded,
      title: route,
      subtitle: 'Estado: ${trip['status']} · Bs ${trip['final_fare'] ?? '-'}',
      onTap: () => _showServiceDetails(
        context,
        service,
        type: 'trip',
        data: trip,
      ),
      action: driverId == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Ver mapa',
                  onPressed: () {
                    final rideMap = ride is Map
                        ? Map<String, dynamic>.from(ride)
                        : <String, dynamic>{};
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceTrackingPage(
                          title: 'Seguimiento del viaje',
                          status: status ?? '',
                          driverId: driverId,
                          pickupLatitude:
                              _asDouble(rideMap['pickup_latitude']),
                          pickupLongitude:
                              _asDouble(rideMap['pickup_longitude']),
                          destinationLatitude:
                              _asDouble(rideMap['destination_latitude']),
                          destinationLongitude:
                              _asDouble(rideMap['destination_longitude']),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_outlined),
                ),
                if (cancellable)
                  IconButton(
                    tooltip: 'Cancelar viaje',
                    onPressed: () => cancel(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final ExpressService service;
  final Map<String, dynamic> delivery;
  final VoidCallback onChanged;
  const _DeliveryCard({
    required this.service,
    required this.delivery,
    required this.onChanged,
  });

  Future<void> cancel(BuildContext context) async {
    final reason = await _askCancellationReason(context, 'delivery');
    if (reason == null || !context.mounted) return;
    try {
      await service.cancelDelivery(
        delivery['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery cancelado.')),
      );
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = delivery['status']?.toString();
    final cancellable = delivery['customer_id'] == service.userId &&
        ['searching', 'accepted'].contains(status);
    final courierId = delivery['courier_id']?.toString();
    return _RecordCard(
      icon: Icons.local_shipping_rounded,
      title: '${delivery['pickup_address']} → ${delivery['dropoff_address']}',
      subtitle: 'Delivery · ${delivery['status']} · Bs ${delivery['proposed_fare']}',
      onTap: () => _showServiceDetails(
        context,
        service,
        type: 'delivery',
        data: delivery,
      ),
      action: courierId == null && !cancellable
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (courierId != null)
                  IconButton(
                    tooltip: 'Ver mapa',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceTrackingPage(
                          title: 'Seguimiento del delivery',
                          status: status ?? '',
                          driverId: courierId,
                          pickupLatitude:
                              _asDouble(delivery['pickup_latitude']),
                          pickupLongitude:
                              _asDouble(delivery['pickup_longitude']),
                          destinationLatitude:
                              _asDouble(delivery['dropoff_latitude']),
                          destinationLongitude:
                              _asDouble(delivery['dropoff_longitude']),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.map_outlined),
                  ),
                if (cancellable)
                  IconButton(
                    tooltip: 'Cancelar delivery',
                    onPressed: () => cancel(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
    );
  }
}

class _PaymentsPage extends StatefulWidget {
  final ExpressService service;
  final int revision;
  const _PaymentsPage({required this.service, required this.revision});

  @override
  State<_PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<_PaymentsPage> {
  int refresh = 0;

  Future<_PaymentsBundle> _load() async {
    final wallet = await widget.service.myWallet();
    final walletMovements = await widget.service.walletTransactions();
    final payments = await widget.service.myPayments();
    return _PaymentsBundle(
      wallet: wallet,
      walletMovements: walletMovements,
      payments: payments,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_PaymentsBundle>(
        key: ValueKey('${widget.revision}-$refresh'),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.all(18),
              children: const [
                _TopBrand(role: 'Pagos'),
                SizedBox(height: 20),
                Text(
                  'Billetera Express',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 14),
                LinearProgressIndicator(),
                SizedBox(height: 14),
                _InfoCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Actualizando billetera',
                  text: 'Estamos sincronizando tu saldo y movimientos.',
                ),
              ],
            );
          }

          if (snapshot.hasError) {
            return _ErrorView(
              error: snapshot.error,
              onRetry: () => setState(() => refresh++),
            );
          }

          final data = snapshot.data ??
              const _PaymentsBundle(
                wallet: <String, dynamic>{},
                walletMovements: <Map<String, dynamic>>[],
                payments: <Map<String, dynamic>>[],
              );
          final balance = data.wallet['balance'] ?? 0;
          final currency = data.wallet['currency'] ?? 'BOB';

          return RefreshIndicator(
            onRefresh: () async => setState(() => refresh++),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Pagos'),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B1739), _blue],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Billetera Express',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '$currency $balance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Saldo disponible',
                        style: TextStyle(color: Color(0xFFDCEAFF)),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Los pagos hechos con Billetera Express se procesan automáticamente al completar el servicio.',
                        style: TextStyle(
                          color: Color(0xFFBFD8FF),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Movimientos de billetera',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                if (data.walletMovements.isEmpty)
                  const _InfoCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'Sin movimientos todavía',
                    text:
                        'Aquí aparecerán pagos, devoluciones y ganancias de la billetera.',
                  )
                else
                  ...data.walletMovements.map((row) {
                    final amount = row['amount'];
                    final positive = amount is num
                        ? amount >= 0
                        : !amount.toString().startsWith('-');
                    return _RecordCard(
                      icon: positive
                          ? Icons.add_circle_outline_rounded
                          : Icons.remove_circle_outline_rounded,
                      title:
                          '${positive ? '+' : ''}${row['amount']} ${data.wallet['currency'] ?? 'BOB'}',
                      subtitle:
                          '${_walletMovementLabel(row['type']?.toString())} · ${row['status'] ?? ''}',
                    );
                  }),
                const SizedBox(height: 22),
                const Text(
                  'Pagos de servicios',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                if (data.payments.isEmpty)
                  const _InfoCard(
                    icon: Icons.payments_outlined,
                    title: 'Sin pagos registrados',
                    text: 'Los pagos de tus viajes y delivery aparecerán aquí.',
                  )
                else
                  ...data.payments.map(
                    (row) => _RecordCard(
                      icon: row['method'] == 'cash'
                          ? Icons.payments_outlined
                          : row['method'] == 'wallet'
                              ? Icons.account_balance_wallet_outlined
                              : Icons.credit_card_rounded,
                      title:
                          '${row['currency'] ?? 'BOB'} ${row['amount']}',
                      subtitle:
                          '${_paymentMethodLabel(row['method']?.toString())} · ${row['status']}',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _walletMovementLabel(String? type) {
    switch (type) {
      case 'topup':
        return 'Recarga';
      case 'payment':
        return 'Pago';
      case 'refund':
        return 'Devolución';
      case 'earning':
        return 'Ganancia';
      case 'adjustment':
        return 'Ajuste';
      default:
        return type ?? 'Movimiento';
    }
  }

  String _paymentMethodLabel(String? method) {
    switch (method) {
      case 'cash':
        return 'Efectivo';
      case 'wallet':
        return 'Billetera';
      case 'card':
        return 'Tarjeta';
      default:
        return method ?? 'Pago';
    }
  }
}

class _PaymentsBundle {
  final Map<String, dynamic> wallet;
  final List<Map<String, dynamic>> walletMovements;
  final List<Map<String, dynamic>> payments;

  const _PaymentsBundle({
    required this.wallet,
    required this.walletMovements,
    required this.payments,
  });
}

class _ProfilePage extends StatefulWidget {
  final ExpressService service;
  final bool driver;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;
  const _ProfilePage({required this.service, required this.driver, required this.onSwitchMode, required this.onExit});

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  int refresh = 0;

  Future<void> _editProfile(Map<String, dynamic>? user) async {
    final nameController = TextEditingController(
      text: user?['full_name']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: user?['phone']?.toString() ?? '',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                prefixIcon: Icon(Icons.phone_outlined),
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (save != true || !mounted) {
      nameController.dispose();
      phoneController.dispose();
      return;
    }

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    nameController.dispose();
    phoneController.dispose();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede quedar vacío.')),
      );
      return;
    }

    try {
      await widget.service.updateProfile(
        fullName: name,
        phone: phone.isEmpty ? null : phone,
      );
      if (!mounted) return;
      setState(() => refresh++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>?>(
        key: ValueKey(refresh),
        future: widget.service.myUser(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          final email = supabase.auth.currentUser?.email ?? '';
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const _TopBrand(role: 'Perfil'),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: _cardDecoration(),
                child: Row(children: [
                  const CircleAvatar(radius: 28, backgroundColor: _blue, child: Icon(Icons.person_rounded, color: Colors.white)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user?['full_name']?.toString().trim().isNotEmpty == true ? user!['full_name'].toString() : 'Usuario Express', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(email, style: const TextStyle(color: _muted)),
                    if (user?['phone'] != null) Text(user!['phone'].toString(), style: const TextStyle(color: _muted)),
                  ])),
                  IconButton(
                    tooltip: 'Editar perfil',
                    onPressed: () => _editProfile(user),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: Text(widget.driver ? 'Cambiar a modo Cliente' : 'Cambiar a modo Conductor'),
                subtitle: Text(widget.driver ? 'Volver a solicitar servicios' : 'Crear o abrir tu perfil de conductor'),
                onTap: widget.onSwitchMode,
              ),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Mis direcciones'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _SavedAddressesPage(service: widget.service))),
              ),
              ListTile(
                leading: const Icon(Icons.security_outlined),
                title: const Text('Seguridad y contactos'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _SafetyPage(service: widget.service))),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Cerrar sesión'),
                onTap: widget.onExit,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DriverShell extends StatefulWidget {
  final ExpressService service;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;
  const _DriverShell({required this.service, required this.onSwitchMode, required this.onExit});

  @override
  State<_DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<_DriverShell> {
  int index = 0;
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DriverMapHome(
        service: widget.service,
        revision: revision,
        onChanged: () => setState(() => revision++),
        onSwitchMode: widget.onSwitchMode,
        onServices: () => setState(() => index = 1),
        onEarnings: () => setState(() => index = 2),
        onProfile: () => setState(() => index = 3),
        onSafety: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SafetyPage(service: widget.service),
          ),
        ),
      ),
      _DriverServices(service: widget.service, revision: revision, onChanged: () => setState(() => revision++)),
      _DriverEarnings(service: widget.service, revision: revision),
      _ProfilePage(service: widget.service, driver: true, onSwitchMode: widget.onSwitchMode, onExit: widget.onExit),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route_rounded), label: 'Servicios'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart_rounded), label: 'Ganancias'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _DriverHome extends StatefulWidget {
  final ExpressService service;
  final int revision;
  final VoidCallback onChanged;
  const _DriverHome({required this.service, required this.revision, required this.onChanged});

  @override
  State<_DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<_DriverHome> {
  int refresh = 0;
  bool busy = false;
  StreamSubscription? _positionSubscription;
  final locationService = const ExpressLocationService();

  void _startLocationTracking() {
    if (_positionSubscription != null) return;
    _positionSubscription = locationService.positionStream().listen(
      (position) async {
        try {
          await widget.service.updateDriverDetails(
            latitude: position.latitude,
            longitude: position.longitude,
          );
        } catch (_) {
          // El siguiente evento volverá a intentar sincronizar la ubicación.
        }
      },
      onError: (_) {},
    );
  }

  Future<void> _stopLocationTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<_DriverBundle> load() async {
    final profile = await widget.service.myDriverProfile() ??
        await widget.service.ensureDriverProfile();
    List<Map<String, dynamic>> rides = [];
    List<Map<String, dynamic>> deliveries = [];

    if (profile['approval_status'] == 'approved' &&
        ['online', 'busy'].contains(profile['online_status'])) {
      _startLocationTracking();

      final vehicles = await widget.service.myVehicles();
      final vehicleTypes = vehicles
          .where((vehicle) => vehicle['is_active'] == true)
          .map((vehicle) => vehicle['vehicle_type']?.toString())
          .whereType<String>()
          .toSet();

      rides = (await widget.service.availableRideRequests())
          .where((ride) => _rideMatchesVehicle(
                ride['category']?.toString() ?? 'economy',
                vehicleTypes,
              ))
          .toList();
      deliveries = await widget.service.availableDeliveries();

      final latitude = _asDouble(profile['latitude']);
      final longitude = _asDouble(profile['longitude']);
      if (latitude != null && longitude != null) {
        double distanceTo(Map<String, dynamic> row, String latKey, String lngKey) {
          final lat = _asDouble(row[latKey]);
          final lng = _asDouble(row[lngKey]);
          if (lat == null || lng == null) return double.infinity;
          return locationService.distanceMeters(
            fromLatitude: latitude,
            fromLongitude: longitude,
            toLatitude: lat,
            toLongitude: lng,
          );
        }

        rides.sort(
          (a, b) => distanceTo(a, 'pickup_latitude', 'pickup_longitude')
              .compareTo(
            distanceTo(b, 'pickup_latitude', 'pickup_longitude'),
          ),
        );
        deliveries.sort(
          (a, b) => distanceTo(a, 'pickup_latitude', 'pickup_longitude')
              .compareTo(
            distanceTo(b, 'pickup_latitude', 'pickup_longitude'),
          ),
        );
      }
    }

    return _DriverBundle(profile, rides, deliveries);
  }

  bool _rideMatchesVehicle(String category, Set<String> vehicleTypes) {
    if (vehicleTypes.isEmpty) return true;

    switch (category) {
      case 'motorcycle':
        return vehicleTypes.contains('motorcycle');
      case 'xl':
        return vehicleTypes.contains('xl');
      case 'comfort':
      case 'economy':
        return vehicleTypes.contains('car') || vehicleTypes.contains('xl');
      default:
        return true;
    }
  }

  String? _distanceLabel(
    Map<String, dynamic> profile,
    Map<String, dynamic> row,
  ) {
    final fromLat = _asDouble(profile['latitude']);
    final fromLng = _asDouble(profile['longitude']);
    final toLat = _asDouble(row['pickup_latitude']);
    final toLng = _asDouble(row['pickup_longitude']);
    if (fromLat == null || fromLng == null || toLat == null || toLng == null) {
      return null;
    }
    final meters = locationService.distanceMeters(
      fromLatitude: fromLat,
      fromLongitude: fromLng,
      toLatitude: toLat,
      toLongitude: toLng,
    );
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> toggleOnline(Map<String, dynamic> profile) async {
    setState(() => busy = true);
    try {
      final online = profile['online_status'] == 'online';
      if (online) {
        await widget.service.setDriverOnline(false);
        await _stopLocationTracking();
      } else {
        final position = await locationService.currentPosition();
        await widget.service.updateDriverDetails(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        await widget.service.setDriverOnline(true);
        _startLocationTracking();
      }
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> offerRide(Map<String, dynamic> ride) async {
    final fareController = TextEditingController(
      text: ride['proposed_fare']?.toString() ?? '',
    );
    final etaController = TextEditingController(text: '5');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar oferta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${ride['pickup_address']} → ${ride['destination_address']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: fareController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tu tarifa (Bs)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: etaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Llegas en (minutos)',
                prefixIcon: Icon(Icons.schedule_rounded),
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enviar oferta'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      fareController.dispose();
      etaController.dispose();
      return;
    }

    final fare = num.tryParse(
      fareController.text.trim().replaceAll(',', '.'),
    );
    final eta = int.tryParse(etaController.text.trim());
    fareController.dispose();
    etaController.dispose();

    if (fare == null || fare <= 0 || eta == null || eta <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa una tarifa y tiempo válidos.'),
        ),
      );
      return;
    }

    try {
      await widget.service.createRideOffer(
        rideRequestId: ride['id'].toString(),
        fare: fare,
        etaMinutes: eta,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oferta enviada al pasajero.')),
      );
      setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar la oferta: $e')),
      );
    }
  }

  Future<void> claimDelivery(Map<String, dynamic> delivery) async {
    try {
      await widget.service.claimDelivery(delivery['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery aceptado.')));
      widget.onChanged();
      setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo aceptar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_DriverBundle>(
        key: ValueKey('${widget.revision}-$refresh'),
        future: load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return _ErrorView(error: snapshot.error, onRetry: () => setState(() => refresh++));
          final data = snapshot.data!;
          final profile = data.profile;
          final approved = profile['approval_status'] == 'approved';
          final online = profile['online_status'] == 'online';
          return RefreshIndicator(
            onRefresh: () async => setState(() => refresh++),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Conductor'),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_blueDark, _blue]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Estado: ${profile['approval_status']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(profile['vehicle_summary']?.toString() ?? 'Completa tus datos de vehículo', style: const TextStyle(color: Color(0xFFDCEAFF))),
                    const SizedBox(height: 14),
                    if (approved)
                      FilledButton.icon(
                        onPressed: busy ? null : () => toggleOnline(profile),
                        icon: Icon(online ? Icons.toggle_on_rounded : Icons.toggle_off_rounded),
                        label: Text(online ? 'Quedar fuera de línea' : 'Ponerme en línea'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _blueDark),
                      )
                    else
                      const Text('Tu cuenta debe ser aprobada antes de recibir solicitudes.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 18),
                if (!approved)
                  const _InfoCard(icon: Icons.hourglass_top_rounded, title: 'Aprobación pendiente', text: 'Ya puedes completar tu perfil; las solicitudes se habilitan cuando el administrador aprueba al conductor.')
                else if (!online)
                  const _InfoCard(icon: Icons.visibility_off_outlined, title: 'Estás fuera de línea', text: 'Activa tu disponibilidad para recibir Viajes y Delivery.')
                else ...[
                  const Text('Viajes disponibles', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  if (data.rides.isEmpty) const Text('No hay viajes nuevos por ahora.', style: TextStyle(color: _muted)),
                  ...data.rides.map((ride) => _JobCard(
                        icon: Icons.local_taxi_rounded,
                        title: '${ride['pickup_address']} → ${ride['destination_address']}',
                        subtitle:
                            'Bs ${ride['proposed_fare']} · ${ride['category']}'
                            '${_distanceLabel(profile, ride) == null ? '' : ' · ${_distanceLabel(profile, ride)}'}',
                        button: 'Enviar oferta',
                        onTap: () => offerRide(ride),
                      )),
                  const SizedBox(height: 18),
                  const Text('Delivery disponibles', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  if (data.deliveries.isEmpty) const Text('No hay delivery nuevos por ahora.', style: TextStyle(color: _muted)),
                  ...data.deliveries.map((delivery) => _JobCard(
                        icon: Icons.local_shipping_rounded,
                        title: '${delivery['pickup_address']} → ${delivery['dropoff_address']}',
                        subtitle:
                            'Bs ${delivery['proposed_fare']} · ${delivery['package_type']}'
                            '${_distanceLabel(profile, delivery) == null ? '' : ' · ${_distanceLabel(profile, delivery)}'}',
                        button: 'Aceptar',
                        onTap: () => claimDelivery(delivery),
                      )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DriverServices extends StatefulWidget {
  final ExpressService service;
  final int revision;
  final VoidCallback onChanged;
  const _DriverServices({required this.service, required this.revision, required this.onChanged});

  @override
  State<_DriverServices> createState() => _DriverServicesState();
}

class _DriverServicesState extends State<_DriverServices> {
  int refresh = 0;

  Future<_ActiveBundle> load() async {
    final trips = await widget.service.myTrips();
    final deliveries = await widget.service.myDeliveries();
    return _ActiveBundle(trips, deliveries);
  }

  String? nextTrip(String status) {
    switch (status) {
      case 'driver_assigned': return 'driver_arriving';
      case 'driver_arriving': return 'driver_waiting';
      case 'driver_waiting': return 'in_progress';
      case 'in_progress': return 'completed';
      default: return null;
    }
  }

  String? nextDelivery(String status) {
    switch (status) {
      case 'accepted': return 'picked_up';
      case 'picked_up': return 'in_transit';
      case 'in_transit': return 'delivered';
      default: return null;
    }
  }

  Future<void> advanceTrip(Map<String, dynamic> trip) async {
    final next = nextTrip(trip['status'].toString());
    if (next == null) return;
    try {
      await widget.service.advanceTrip(trip['id'].toString(), next);
      if (mounted) setState(() => refresh++);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo avanzar el viaje: $e')));
    }
  }

  Future<void> advanceDelivery(Map<String, dynamic> delivery) async {
    final next = nextDelivery(delivery['status'].toString());
    if (next == null) return;
    try {
      await widget.service.advanceDelivery(delivery['id'].toString(), next);
      if (mounted) setState(() => refresh++);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo avanzar el delivery: $e')));
    }
  }

  Future<void> cancelTrip(Map<String, dynamic> trip) async {
    final reason = await _askCancellationReason(context, 'viaje');
    if (reason == null || !mounted) return;
    try {
      await widget.service.cancelTrip(
        trip['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (mounted) setState(() => refresh++);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar el viaje: $e')),
      );
    }
  }

  Future<void> cancelDelivery(Map<String, dynamic> delivery) async {
    final reason = await _askCancellationReason(context, 'delivery');
    if (reason == null || !mounted) return;
    try {
      await widget.service.cancelDelivery(
        delivery['id'].toString(),
        reason: reason.isEmpty ? null : reason,
      );
      if (mounted) setState(() => refresh++);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar el delivery: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_ActiveBundle>(
        key: ValueKey('${widget.revision}-$refresh'),
        future: load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return _ErrorView(error: snapshot.error, onRetry: () => setState(() => refresh++));
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => refresh++),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Servicios'),
                const SizedBox(height: 20),
                const Text('Servicios asignados', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                ...data.trips.map((trip) {
                  final ride = trip['ride_requests'];
                  final route = ride is Map ? '${ride['pickup_address']} → ${ride['destination_address']}' : 'Viaje';
                  final next = nextTrip(trip['status'].toString());
                  return _RecordCard(
                    icon: Icons.local_taxi_rounded,
                    title: route,
                    subtitle: 'Viaje · ${trip['status']} · Bs ${trip['final_fare'] ?? '-'}',
                    action: next == null
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Ver mapa',
                                onPressed: () {
                                  final rideMap = ride is Map
                                      ? Map<String, dynamic>.from(ride)
                                      : <String, dynamic>{};
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ServiceTrackingPage(
                                        title: 'Ruta del viaje',
                                        status: trip['status']?.toString() ?? '',
                                        driverId: widget.service.userId,
                                        pickupLatitude:
                                            _asDouble(rideMap['pickup_latitude']),
                                        pickupLongitude:
                                            _asDouble(rideMap['pickup_longitude']),
                                        destinationLatitude:
                                            _asDouble(rideMap['destination_latitude']),
                                        destinationLongitude:
                                            _asDouble(rideMap['destination_longitude']),
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.map_outlined),
                              ),
                              FilledButton(
                                onPressed: () => advanceTrip(trip),
                                child: Text(_tripAction(next)),
                              ),
                              if (['driver_assigned', 'driver_arriving', 'driver_waiting']
                                  .contains(trip['status']))
                                IconButton(
                                  tooltip: 'Cancelar viaje',
                                  onPressed: () => cancelTrip(trip),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                  );
                }),
                ...data.deliveries.where((d) => d['courier_id'] == widget.service.userId).map((delivery) {
                  final next = nextDelivery(delivery['status'].toString());
                  return _RecordCard(
                    icon: Icons.local_shipping_rounded,
                    title: '${delivery['pickup_address']} → ${delivery['dropoff_address']}',
                    subtitle: 'Delivery · ${delivery['status']} · Bs ${delivery['proposed_fare']}',
                    action: next == null
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Ver mapa',
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ServiceTrackingPage(
                                      title: 'Ruta del delivery',
                                      status: delivery['status']?.toString() ?? '',
                                      driverId: widget.service.userId,
                                      pickupLatitude:
                                          _asDouble(delivery['pickup_latitude']),
                                      pickupLongitude:
                                          _asDouble(delivery['pickup_longitude']),
                                      destinationLatitude:
                                          _asDouble(delivery['dropoff_latitude']),
                                      destinationLongitude:
                                          _asDouble(delivery['dropoff_longitude']),
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.map_outlined),
                              ),
                              FilledButton(
                                onPressed: () => advanceDelivery(delivery),
                                child: Text(_deliveryAction(next)),
                              ),
                              if (delivery['status'] == 'accepted')
                                IconButton(
                                  tooltip: 'Cancelar delivery',
                                  onPressed: () => cancelDelivery(delivery),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                  );
                }),
                if (data.trips.isEmpty && data.deliveries.where((d) => d['courier_id'] == widget.service.userId).isEmpty)
                  const _InfoCard(icon: Icons.route_outlined, title: 'Sin servicios asignados', text: 'Los viajes elegidos por pasajeros y los delivery aceptados aparecerán aquí.'),
              ],
            ),
          );
        },
      ),
    );
  }

  String _tripAction(String status) {
    switch (status) {
      case 'driver_arriving': return 'Ir al pasajero';
      case 'driver_waiting': return 'Llegué';
      case 'in_progress': return 'Iniciar viaje';
      case 'completed': return 'Completar';
      default: return status;
    }
  }

  String _deliveryAction(String status) {
    switch (status) {
      case 'picked_up': return 'Recogido';
      case 'in_transit': return 'En camino';
      case 'delivered': return 'Entregado';
      default: return status;
    }
  }
}

class _DriverEarnings extends StatefulWidget {
  final ExpressService service;
  final int revision;
  const _DriverEarnings({
    required this.service,
    required this.revision,
  });

  @override
  State<_DriverEarnings> createState() => _DriverEarningsState();
}

class _DriverEarningsState extends State<_DriverEarnings> {
  String period = 'today';
  int refresh = 0;

  DateTime? _fromDate() {
    final now = DateTime.now();
    switch (period) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'week':
        final today = DateTime(now.year, now.month, now.day);
        return today.subtract(Duration(days: today.weekday - 1));
      case 'month':
        return DateTime(now.year, now.month, 1);
      default:
        return null;
    }
  }

  bool _inPeriod(Map<String, dynamic> row) {
    final from = _fromDate();
    if (from == null) return true;
    final raw = row['completed_at'] ?? row['created_at'];
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return false;
    return !date.isBefore(from);
  }

  Future<_EarningsBundle> load() async {
    final trips = await widget.service.myTrips();
    final deliveries = await widget.service.myDeliveries();

    final completedTrips = trips
        .where(
          (t) =>
              t['driver_id'] == widget.service.userId &&
              t['status'] == 'completed' &&
              _inPeriod(t),
        )
        .toList();

    final completedDeliveries = deliveries
        .where(
          (d) =>
              d['courier_id'] == widget.service.userId &&
              d['status'] == 'delivered' &&
              _inPeriod(d),
        )
        .toList();

    num total = 0;
    for (final trip in completedTrips) {
      total += (trip['final_fare'] as num?) ?? 0;
    }
    for (final delivery in completedDeliveries) {
      total += (delivery['proposed_fare'] as num?) ?? 0;
    }

    return _EarningsBundle(
      total,
      completedTrips.length + completedDeliveries.length,
      completedTrips,
      completedDeliveries,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_EarningsBundle>(
        key: ValueKey('${widget.revision}-$refresh-$period'),
        future: load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              error: snapshot.error,
              onRetry: () => setState(() => refresh++),
            );
          }

          final data = snapshot.data!;
          final tripTotal = data.trips.fold<num>(
            0,
            (sum, trip) => sum + ((trip['final_fare'] as num?) ?? 0),
          );
          final deliveryTotal = data.deliveries.fold<num>(
            0,
            (sum, delivery) =>
                sum + ((delivery['proposed_fare'] as num?) ?? 0),
          );
          final average = data.count == 0 ? 0 : data.total / data.count;

          return RefreshIndicator(
            onRefresh: () async => setState(() => refresh++),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _TopBrand(role: 'Ganancias'),
                const SizedBox(height: 20),
                const Text(
                  'Tus ganancias',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _EarningsPeriodChip(
                        label: 'Hoy',
                        selected: period == 'today',
                        onTap: () => setState(() => period = 'today'),
                      ),
                      _EarningsPeriodChip(
                        label: 'Esta semana',
                        selected: period == 'week',
                        onTap: () => setState(() => period = 'week'),
                      ),
                      _EarningsPeriodChip(
                        label: 'Este mes',
                        selected: period == 'month',
                        onTap: () => setState(() => period = 'month'),
                      ),
                      _EarningsPeriodChip(
                        label: 'Todo',
                        selected: period == 'all',
                        onTap: () => setState(() => period = 'all'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_blueDark, _blue],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ganancia registrada',
                        style: TextStyle(color: Color(0xFFDCEAFF)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Bs ${data.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${data.count} servicios · promedio Bs ${average.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _EarningMetric(
                        icon: Icons.local_taxi_rounded,
                        label: 'Viajes',
                        amount: tripTotal,
                        count: data.trips.length,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _EarningMetric(
                        icon: Icons.local_shipping_rounded,
                        label: 'Delivery',
                        amount: deliveryTotal,
                        count: data.deliveries.length,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (data.count == 0)
                  const _InfoCard(
                    icon: Icons.payments_outlined,
                    title: 'Sin ganancias en este período',
                    text:
                        'Los servicios completados aparecerán aquí automáticamente.',
                  )
                else ...[
                  const Text(
                    'Detalle',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...data.trips.map(
                    (trip) => _RecordCard(
                      icon: Icons.local_taxi_rounded,
                      title: 'Viaje completado',
                      subtitle:
                          'Bs ${trip['final_fare'] ?? 0} · ${_shortServiceDate(trip['completed_at'] ?? trip['created_at'])}',
                    ),
                  ),
                  ...data.deliveries.map(
                    (delivery) => _RecordCard(
                      icon: Icons.local_shipping_rounded,
                      title: 'Delivery entregado',
                      subtitle:
                          'Bs ${delivery['proposed_fare'] ?? 0} · ${_shortServiceDate(delivery['completed_at'] ?? delivery['created_at'])}',
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EarningsPeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _EarningsPeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        label: Text(label),
        selectedColor: const Color(0xFFEAF2FF),
        side: BorderSide(
          color: selected ? _blue : const Color(0xFFE4E7EC),
        ),
        labelStyle: TextStyle(
          color: selected ? _blue : _muted,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

class _EarningMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final num amount;
  final int count;

  const _EarningMetric({
    required this.icon,
    required this.label,
    required this.amount,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _blue),
          const SizedBox(height: 8),
          Text(
            'Bs ${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '$count $label',
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

String _shortServiceDate(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (date == null) return '—';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month · $hour:$minute';
}

class _SavedAddressesPage extends StatefulWidget {
  final ExpressService service;
  const _SavedAddressesPage({required this.service});
  @override
  State<_SavedAddressesPage> createState() => _SavedAddressesPageState();
}

class _SavedAddressesPageState extends State<_SavedAddressesPage> {
  int refresh = 0;

  Future<void> add() async {
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationPickerPage(
          title: 'Guardar dirección',
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final labelController = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nombre de la dirección'),
        content: TextField(
          controller: labelController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Ej. Casa, Trabajo',
            helperText: picked.label,
          ),
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

    final label = labelController.text.trim();
    labelController.dispose();
    if (save != true || label.isEmpty || !mounted) return;

    try {
      await widget.service.addSavedAddress(
        label: label,
        address: picked.label,
        latitude: picked.latitude,
        longitude: picked.longitude,
      );
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  Future<void> remove(Map<String, dynamic> row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar dirección'),
        content: Text(
          '¿Eliminar ${row['label'] ?? 'esta dirección'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await widget.service.deleteSavedAddress(row['id'].toString());
    if (mounted) setState(() => refresh++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mis direcciones')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: add,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Agregar'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(refresh),
          future: widget.service.savedAddresses(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return const Center(
                child: Text('Todavía no tienes direcciones guardadas.'),
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: rows
                  .map(
                    (row) => ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.location_on_outlined),
                      ),
                      title: Text(row['label'].toString()),
                      subtitle: Text(row['address'].toString()),
                      trailing: IconButton(
                        tooltip: 'Eliminar',
                        onPressed: () => remove(row),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
}

class _SafetyPage extends StatefulWidget {
  final ExpressService service;
  const _SafetyPage({required this.service});
  @override
  State<_SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends State<_SafetyPage> {
  int refresh = 0;
  Future<void> addContact() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contacto de confianza'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
            await widget.service.addTrustedContact(name: name.text.trim(), phone: phone.text.trim());
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (mounted) setState(() => refresh++);
          }, child: const Text('Guardar')),
        ],
      ),
    );
  }

  Future<void> sos() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activar SOS'),
        content: const Text(
          'Se registrará una alerta de emergencia y, si tienes un servicio activo, quedará vinculada al Viaje o Delivery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Activar SOS'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      String? tripId;
      String? deliveryId;
      double? latitude;
      double? longitude;

      final trips = await widget.service.myTrips();
      for (final trip in trips) {
        final status = trip['status']?.toString();
        if (!['completed', 'cancelled'].contains(status)) {
          tripId = trip['id']?.toString();
          break;
        }
      }

      if (tripId == null) {
        final deliveries = await widget.service.myDeliveries();
        for (final delivery in deliveries) {
          final status = delivery['status']?.toString();
          if (!['delivered', 'cancelled'].contains(status) &&
              delivery['courier_id'] != null) {
            deliveryId = delivery['id']?.toString();
            break;
          }
        }
      }

      try {
        final position =
            await const ExpressLocationService().currentPosition();
        latitude = position.latitude;
        longitude = position.longitude;
      } catch (_) {
        // El SOS sigue funcionando incluso si no hay GPS disponible.
      }

      await widget.service.createEmergency(
        tripId: tripId,
        deliveryId: deliveryId,
        latitude: latitude,
        longitude: longitude,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alerta SOS registrada y enviada al sistema.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar la alerta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seguridad')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(refresh),
      future: widget.service.trustedContacts(),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            FilledButton.icon(onPressed: sos, style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(56)), icon: const Icon(Icons.sos_rounded), label: const Text('Activar SOS')),
            const SizedBox(height: 20),
            Row(children: [const Expanded(child: Text('Contactos de confianza', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), IconButton(onPressed: addContact, icon: const Icon(Icons.person_add_alt_1_rounded))]),
            if (snapshot.connectionState == ConnectionState.waiting) const Center(child: CircularProgressIndicator()),
            if (rows.isEmpty && snapshot.connectionState != ConnectionState.waiting) const Text('Todavía no tienes contactos guardados.'),
            ...rows.map((row) => ListTile(leading: const Icon(Icons.contact_phone_outlined), title: Text(row['name'].toString()), subtitle: Text(row['phone'].toString()))),
          ],
        );
      },
    ),
  );
}

class _ActivityBundle {
  final List<Map<String, dynamic>> rides;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> deliveries;
  _ActivityBundle(this.rides, this.trips, this.deliveries);
}

class _DriverBundle {
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> rides;
  final List<Map<String, dynamic>> deliveries;
  _DriverBundle(this.profile, this.rides, this.deliveries);
}

class _ActiveBundle {
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> deliveries;
  _ActiveBundle(this.trips, this.deliveries);
}

class _EarningsBundle {
  final num total;
  final int count;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> deliveries;
  _EarningsBundle(this.total, this.count, this.trips, this.deliveries);
}

class _TopBrand extends StatelessWidget {
  final String role;
  const _TopBrand({required this.role});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 44, height: 44, decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.bolt_rounded, color: Colors.white)),
    const SizedBox(width: 10),
    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('EXPRESS', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), Text('Viajes · Delivery', style: TextStyle(color: _muted, fontSize: 11))]),
    const Spacer(),
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(999)), child: Text(role, style: const TextStyle(color: _blue, fontSize: 11, fontWeight: FontWeight.w800))),
  ]);
}

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback onTap;
  final bool dark;
  const _ServiceCard({required this.icon, required this.title, required this.subtitle, required this.button, required this.onTap, this.dark = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: _cardDecoration(),
    child: Row(children: [
      Container(width: 68, height: 68, decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(20)), child: Icon(icon, color: dark ? _blueDark : _blue, size: 36)),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: _muted)), const SizedBox(height: 10), FilledButton(onPressed: onTap, style: FilledButton.styleFrom(backgroundColor: dark ? _blueDark : _blue), child: Text(button))])),
    ]),
  );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _InfoCard({required this.icon, required this.title, required this.text});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: _cardDecoration(), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: _blue), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(text, style: const TextStyle(color: _muted))]))]));
}

class _RecordCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final VoidCallback? onTap;

  const _RecordCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              padding: const EdgeInsets.all(15),
              decoration: _cardDecoration(),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFEAF2FF),
                    child: Icon(icon, color: _blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                          ),
                        ),
                        if (onTap != null) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Toca para ver detalles',
                            style: TextStyle(
                              color: _blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(width: 8),
                    action!,
                  ] else if (onTap != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _muted,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _JobCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback onTap;
  const _JobCard({required this.icon, required this.title, required this.subtitle, required this.button, required this.onTap});
  @override
  Widget build(BuildContext context) => _RecordCard(icon: icon, title: title, subtitle: subtitle, action: FilledButton(onPressed: onTap, child: Text(button)));
}

class _ErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline_rounded, size: 44), const SizedBox(height: 10), Text('Error: $error', textAlign: TextAlign.center), const SizedBox(height: 14), FilledButton(onPressed: onRetry, child: const Text('Reintentar'))])));
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: const Color(0xFFE4E9F0)),
  boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 18, offset: Offset(0, 7))],
);

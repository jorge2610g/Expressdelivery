import 'package:flutter/material.dart';

const expressPreviewVersion = 'v1.1.0 · build 8';
const _blue = Color(0xFF0B57D0);
const _blueDark = Color(0xFF073B8C);
const _yellow = Color(0xFFFFC928);
const _bg = Color(0xFFF5F7FB);
const _text = Color(0xFF101828);
const _muted = Color(0xFF667085);

enum ExperienceMode { customer, driver }

enum ServiceKind { ride, delivery }

class PreviewActivity {
  final ServiceKind kind;
  final String title;
  final String route;
  final String amount;
  final String status;
  final IconData icon;

  const PreviewActivity({
    required this.kind,
    required this.title,
    required this.route,
    required this.amount,
    required this.status,
    required this.icon,
  });
}

class ExpressExperiencePreview extends StatefulWidget {
  final VoidCallback onExit;

  const ExpressExperiencePreview({super.key, required this.onExit});

  @override
  State<ExpressExperiencePreview> createState() => _ExpressExperiencePreviewState();
}

class _ExpressExperiencePreviewState extends State<ExpressExperiencePreview> {
  ExperienceMode mode = ExperienceMode.customer;
  final List<PreviewActivity> activity = [
    const PreviewActivity(
      kind: ServiceKind.ride,
      title: 'Viaje completado',
      route: 'Centro → Paitití',
      amount: 'Bs 12',
      status: 'Completado',
      icon: Icons.local_taxi_rounded,
    ),
    const PreviewActivity(
      kind: ServiceKind.delivery,
      title: 'Delivery entregado',
      route: 'Pompeya → 13 de Abril',
      amount: 'Bs 10',
      status: 'Entregado',
      icon: Icons.local_shipping_rounded,
    ),
  ];

  void _addActivity(PreviewActivity value) {
    setState(() => activity.insert(0, value));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
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
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _blue, width: 1.6),
          ),
        ),
      ),
      child: mode == ExperienceMode.customer
          ? CustomerShell(
              activity: activity,
              onActivity: _addActivity,
              onSwitchMode: () => setState(() => mode = ExperienceMode.driver),
              onExit: widget.onExit,
            )
          : DriverShell(
              activity: activity,
              onActivity: _addActivity,
              onSwitchMode: () => setState(() => mode = ExperienceMode.customer),
              onExit: widget.onExit,
            ),
    );
  }
}

class CustomerShell extends StatefulWidget {
  final List<PreviewActivity> activity;
  final ValueChanged<PreviewActivity> onActivity;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;

  const CustomerShell({
    super.key,
    required this.activity,
    required this.onActivity,
    required this.onSwitchMode,
    required this.onExit,
  });

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      CustomerHome(onActivity: widget.onActivity),
      ActivityPage(activity: widget.activity, title: 'Mis servicios'),
      const PaymentsPage(),
      ProfilePage(
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

class CustomerHome extends StatelessWidget {
  final ValueChanged<PreviewActivity> onActivity;

  const CustomerHome({super.key, required this.onActivity});

  Future<void> _openRide(BuildContext context) async {
    final result = await Navigator.of(context).push<PreviewActivity>(
      MaterialPageRoute(builder: (_) => const RideBookingPage()),
    );
    if (result != null) onActivity(result);
  }

  Future<void> _openDelivery(BuildContext context) async {
    final result = await Navigator.of(context).push<PreviewActivity>(
      MaterialPageRoute(builder: (_) => const DeliveryBookingPage()),
    );
    if (result != null) onActivity(result);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          const _TopBrand(role: 'Pasajero / Cliente'),
          const SizedBox(height: 22),
          const Text('¿Qué necesitas hoy?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.7)),
          const SizedBox(height: 6),
          const Text('Viajes y envíos desde una sola aplicación.', style: TextStyle(color: _muted, fontSize: 15)),
          const SizedBox(height: 22),
          _HeroServiceCard(
            icon: Icons.local_taxi_rounded,
            title: 'Pedir un viaje',
            subtitle: 'Muévete por tu ciudad de forma segura.',
            button: 'Solicitar viaje',
            accent: _blue,
            onTap: () => _openRide(context),
          ),
          const SizedBox(height: 14),
          _HeroServiceCard(
            icon: Icons.local_shipping_rounded,
            title: 'Enviar un delivery',
            subtitle: 'Paquetes, documentos y compras.',
            button: 'Crear envío',
            accent: _blueDark,
            onTap: () => _openDelivery(context),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _QuickAction(icon: Icons.shield_outlined, label: 'Seguridad', onTap: () => _sheet(context, 'Seguridad', 'Botón de pánico, compartir viaje y contactos de confianza.'))),
              const SizedBox(width: 10),
              Expanded(child: _QuickAction(icon: Icons.discount_outlined, label: 'Promos', onTap: () => _sheet(context, 'Promociones', 'Aquí aparecerán cupones y beneficios disponibles.'))),
              const SizedBox(width: 10),
              Expanded(child: _QuickAction(icon: Icons.support_agent_rounded, label: 'Ayuda', onTap: () => _sheet(context, 'Centro de ayuda', 'Soporte, preguntas frecuentes y reporte de problemas.'))),
            ],
          ),
          const SizedBox(height: 26),
          const Text('Actividad reciente', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const _MiniActivity(icon: Icons.local_taxi_rounded, title: 'Centro → Paitití', subtitle: 'Viaje completado · Bs 12'),
          const SizedBox(height: 10),
          const _MiniActivity(icon: Icons.local_shipping_rounded, title: 'Pompeya → 13 de Abril', subtitle: 'Delivery entregado · Bs 10'),
        ],
      ),
    );
  }
}

class RideBookingPage extends StatefulWidget {
  const RideBookingPage({super.key});

  @override
  State<RideBookingPage> createState() => _RideBookingPageState();
}

class _RideBookingPageState extends State<RideBookingPage> {
  final from = TextEditingController(text: 'Mi ubicación actual');
  final to = TextEditingController(text: 'Av. Paitití');
  int vehicle = 0;
  int stage = 0;

  final vehicles = const [
    ('Express', 'Bs 5', '3 min', Icons.directions_car_filled_rounded),
    ('Comfort', 'Bs 7', '4 min', Icons.local_taxi_rounded),
    ('XL', 'Bs 10', '5 min', Icons.airport_shuttle_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    if (stage > 0) return _rideProgress(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar viaje')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(controller: from, decoration: const InputDecoration(labelText: 'Punto de partida', prefixIcon: Icon(Icons.my_location_rounded))),
          const SizedBox(height: 12),
          TextField(controller: to, decoration: const InputDecoration(labelText: '¿A dónde vas?', prefixIcon: Icon(Icons.location_on_rounded))),
          const SizedBox(height: 16),
          const _MapSurface(height: 260, car: true),
          const SizedBox(height: 16),
          const Text('Elige tu vehículo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...List.generate(vehicles.length, (i) {
            final item = vehicles[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => setState(() => vehicle = i),
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: vehicle == i ? _blue : const Color(0xFFE4E9F0), width: vehicle == i ? 2 : 1),
                  ),
                  child: Row(children: [
                    CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(item.$4, color: _blue)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${item.$3} de llegada', style: const TextStyle(color: _muted, fontSize: 12)),
                    ])),
                    Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                  ]),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          _PrimaryButton(label: 'Solicitar ${vehicles[vehicle].$1} · ${vehicles[vehicle].$2}', icon: Icons.local_taxi_rounded, onPressed: () => setState(() => stage = 1)),
        ],
      ),
    );
  }

  Widget _rideProgress(BuildContext context) {
    final searching = stage == 1;
    final assigned = stage == 2;
    final inRide = stage == 3;
    return Scaffold(
      appBar: AppBar(title: Text(searching ? 'Buscando conductor' : inRide ? 'En viaje' : 'Conductor asignado')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const _MapSurface(height: 330, car: true),
          const SizedBox(height: 16),
          if (searching)
            _StatusPanel(
              icon: Icons.radar_rounded,
              title: 'Buscando el mejor conductor',
              subtitle: 'Estamos consultando conductores cercanos.',
              trailing: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else
            const _DriverCard(),
          const SizedBox(height: 14),
          if (assigned || inRide) const _TripInfoCard(),
          const SizedBox(height: 14),
          if (searching)
            _PrimaryButton(label: 'Simular conductor encontrado', icon: Icons.person_search_rounded, onPressed: () => setState(() => stage = 2))
          else if (assigned)
            _PrimaryButton(label: 'Iniciar viaje', icon: Icons.play_arrow_rounded, onPressed: () => setState(() => stage = 3))
          else if (inRide)
            _PrimaryButton(label: 'Completar viaje', icon: Icons.flag_rounded, onPressed: () => _completeRide(context)),
          if (!searching) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () => _sheet(context, 'Seguridad', 'El botón de pánico compartiría ubicación y datos del viaje con contactos definidos.'), icon: const Icon(Icons.sos_rounded), label: const Text('Seguridad / Botón de pánico')),
          ],
        ],
      ),
    );
  }

  Future<void> _completeRide(BuildContext context) async {
    final rating = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _RatingSheet(),
    );
    if (!mounted) return;
    Navigator.pop(
      context,
      PreviewActivity(
        kind: ServiceKind.ride,
        title: rating == null ? 'Viaje completado' : 'Viaje completado · $rating★',
        route: '${from.text} → ${to.text}',
        amount: vehicles[vehicle].$2,
        status: 'Completado',
        icon: Icons.local_taxi_rounded,
      ),
    );
  }
}

class DeliveryBookingPage extends StatefulWidget {
  const DeliveryBookingPage({super.key});

  @override
  State<DeliveryBookingPage> createState() => _DeliveryBookingPageState();
}

class _DeliveryBookingPageState extends State<DeliveryBookingPage> {
  final pickup = TextEditingController(text: 'Av. 6 de Agosto');
  final dropoff = TextEditingController(text: 'Calle Paitití');
  final details = TextEditingController(text: 'Caja pequeña');
  int package = 1;
  int stage = 0;

  @override
  Widget build(BuildContext context) {
    if (stage == 1) return _confirmation(context);
    if (stage >= 2) return _tracking(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo envío')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(controller: pickup, decoration: const InputDecoration(labelText: 'Dirección de recogida', prefixIcon: Icon(Icons.trip_origin_rounded))),
          const SizedBox(height: 12),
          TextField(controller: dropoff, decoration: const InputDecoration(labelText: 'Dirección de entrega', prefixIcon: Icon(Icons.location_on_rounded))),
          const SizedBox(height: 18),
          const Text('¿Qué vas a enviar?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _PackageChoice(selected: package == 0, icon: Icons.description_outlined, label: 'Documento', onTap: () => setState(() => package = 0))),
            const SizedBox(width: 10),
            Expanded(child: _PackageChoice(selected: package == 1, icon: Icons.inventory_2_outlined, label: 'Paquete', onTap: () => setState(() => package = 1))),
            const SizedBox(width: 10),
            Expanded(child: _PackageChoice(selected: package == 2, icon: Icons.more_horiz_rounded, label: 'Otro', onTap: () => setState(() => package = 2))),
          ]),
          const SizedBox(height: 14),
          TextField(controller: details, maxLines: 2, decoration: const InputDecoration(labelText: 'Detalles del paquete')),
          const SizedBox(height: 18),
          const _InfoStrip(icon: Icons.shield_outlined, text: 'El conductor verá solo la información necesaria para realizar el envío.'),
          const SizedBox(height: 18),
          _PrimaryButton(label: 'Continuar', icon: Icons.arrow_forward_rounded, onPressed: () => setState(() => stage = 1)),
        ],
      ),
    );
  }

  Widget _confirmation(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar envío')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const _MapSurface(height: 300, car: false),
          const SizedBox(height: 16),
          _RouteSummary(from: pickup.text, to: dropoff.text),
          const SizedBox(height: 12),
          const _PriceRow(label: 'Tarifa estimada', value: 'Bs 8'),
          const _PriceRow(label: 'Tiempo estimado', value: '18–25 min'),
          const SizedBox(height: 18),
          _PrimaryButton(label: 'Confirmar envío · Bs 8', icon: Icons.local_shipping_rounded, onPressed: () => setState(() => stage = 2)),
        ],
      ),
    );
  }

  Widget _tracking(BuildContext context) {
    const labels = ['Conductor asignado', 'Recogiendo paquete', 'En camino a entregar', 'Entregado'];
    final active = stage - 2;
    return Scaffold(
      appBar: AppBar(title: Text(active >= 3 ? 'Entregado' : 'Seguimiento del delivery')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const _MapSurface(height: 250, car: false),
          const SizedBox(height: 14),
          const _DriverCard(delivery: true),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: Column(
              children: List.generate(labels.length, (i) => _TimelineStep(label: labels[i], done: i <= active, last: i == labels.length - 1)),
            ),
          ),
          const SizedBox(height: 16),
          if (active < 3)
            _PrimaryButton(label: 'Avanzar estado de prueba', icon: Icons.sync_rounded, onPressed: () => setState(() => stage += 1))
          else
            _PrimaryButton(
              label: 'Finalizar',
              icon: Icons.check_circle_rounded,
              onPressed: () => Navigator.pop(
                context,
                PreviewActivity(kind: ServiceKind.delivery, title: 'Delivery entregado', route: '${pickup.text} → ${dropoff.text}', amount: 'Bs 8', status: 'Entregado', icon: Icons.local_shipping_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class ActivityPage extends StatelessWidget {
  final List<PreviewActivity> activity;
  final String title;

  const ActivityPage({super.key, required this.activity, required this.title});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const _TopBrand(role: 'Historial'),
          const SizedBox(height: 22),
          Text(title, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...activity.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: _cardDecoration(),
                  child: Row(children: [
                    CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(item.icon, color: _blue)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(item.route, style: const TextStyle(color: _muted, fontSize: 13)),
                      const SizedBox(height: 3),
                      Text(item.status, style: const TextStyle(color: Color(0xFF12B76A), fontWeight: FontWeight.w700, fontSize: 12)),
                    ])),
                    Text(item.amount, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ]),
                ),
              )),
        ],
      ),
    );
  }
}

class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const _TopBrand(role: 'Pagos'),
          const SizedBox(height: 22),
          const Text('Métodos de pago', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          _PaymentTile(icon: Icons.payments_outlined, title: 'Efectivo', subtitle: 'Predeterminado', trailing: 'Activo'),
          const SizedBox(height: 10),
          _PaymentTile(icon: Icons.credit_card_rounded, title: 'Tarjeta', subtitle: 'Agregar tarjeta', trailing: 'Agregar'),
          const SizedBox(height: 10),
          _PaymentTile(icon: Icons.account_balance_wallet_outlined, title: 'Billetera Express', subtitle: 'Saldo disponible', trailing: 'Bs 0'),
          const SizedBox(height: 22),
          const _InfoStrip(icon: Icons.lock_outline_rounded, text: 'Los métodos digitales quedarán conectados a la pasarela de pago que definamos para producción.'),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  final bool driver;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;

  const ProfilePage({super.key, required this.driver, required this.onSwitchMode, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const _TopBrand(role: 'Perfil'),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: const Row(children: [
              CircleAvatar(radius: 28, backgroundColor: _blue, child: Icon(Icons.person_rounded, color: Colors.white, size: 30)),
              SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Usuario Express', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text('usuario@express.app', style: TextStyle(color: _muted)),
              ])),
            ]),
          ),
          const SizedBox(height: 14),
          _SettingsTile(icon: Icons.swap_horiz_rounded, title: driver ? 'Cambiar a modo Cliente' : 'Cambiar a modo Conductor', onTap: onSwitchMode, highlight: true),
          _SettingsTile(icon: Icons.location_on_outlined, title: 'Mis direcciones', onTap: () => _sheet(context, 'Mis direcciones', 'Casa, trabajo y direcciones favoritas.')),
          _SettingsTile(icon: Icons.notifications_none_rounded, title: 'Notificaciones', onTap: () => _sheet(context, 'Notificaciones', 'Viajes, delivery, promociones y alertas de seguridad.')),
          _SettingsTile(icon: Icons.security_outlined, title: 'Seguridad', onTap: () => _sheet(context, 'Seguridad', 'Contactos de confianza, botón de pánico y compartir servicio.')),
          _SettingsTile(icon: Icons.help_outline_rounded, title: 'Ayuda y soporte', onTap: () => _sheet(context, 'Ayuda', 'Centro de ayuda y reporte de problemas.')),
          _SettingsTile(icon: Icons.logout_rounded, title: 'Volver al login', onTap: onExit),
          const SizedBox(height: 16),
          const Center(child: Text(expressPreviewVersion, style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class DriverShell extends StatefulWidget {
  final List<PreviewActivity> activity;
  final ValueChanged<PreviewActivity> onActivity;
  final VoidCallback onSwitchMode;
  final VoidCallback onExit;

  const DriverShell({
    super.key,
    required this.activity,
    required this.onActivity,
    required this.onSwitchMode,
    required this.onExit,
  });

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int index = 0;
  bool online = true;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DriverHome(online: online, onOnline: (v) => setState(() => online = v), onActivity: widget.onActivity),
      ActivityPage(activity: widget.activity, title: 'Historial del conductor'),
      const EarningsPage(),
      ProfilePage(driver: true, onSwitchMode: widget.onSwitchMode, onExit: widget.onExit),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Historial'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart_rounded), label: 'Ganancias'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
        ],
      ),
    );
  }
}

class DriverHome extends StatefulWidget {
  final bool online;
  final ValueChanged<bool> onOnline;
  final ValueChanged<PreviewActivity> onActivity;

  const DriverHome({super.key, required this.online, required this.onOnline, required this.onActivity});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  int serviceTab = 0;

  Future<void> _accept(BuildContext context, ServiceKind kind) async {
    final result = await Navigator.of(context).push<PreviewActivity>(MaterialPageRoute(builder: (_) => DriverActiveServicePage(kind: kind)));
    if (result != null) widget.onActivity(result);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
              const Row(children: [
                CircleAvatar(radius: 26, backgroundColor: Colors.white, child: Icon(Icons.person_rounded, color: _blue)),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Carlos Mendoza', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                  Text('★ 4.9 · Toyota Corolla', style: TextStyle(color: Color(0xFFDCEAFF))),
                ])),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: _DriverMetric(label: 'Servicios', value: '12')),
                const SizedBox(width: 10),
                Expanded(child: _DriverMetric(label: 'Hoy', value: 'Bs 85')),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Icon(widget.online ? Icons.circle : Icons.circle_outlined, size: 14, color: widget.online ? const Color(0xFF12B76A) : _muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(widget.online ? 'En línea y recibiendo solicitudes' : 'Fuera de línea', style: const TextStyle(fontWeight: FontWeight.w700))),
                  Switch(value: widget.online, onChanged: widget.onOnline),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Viajes'), icon: Icon(Icons.local_taxi_rounded)),
              ButtonSegment(value: 1, label: Text('Delivery'), icon: Icon(Icons.local_shipping_rounded)),
            ],
            selected: {serviceTab},
            onSelectionChanged: (v) => setState(() => serviceTab = v.first),
          ),
          const SizedBox(height: 18),
          Text(serviceTab == 0 ? 'Viajes disponibles' : 'Pedidos disponibles', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (!widget.online)
            const _InfoStrip(icon: Icons.visibility_off_outlined, text: 'Ponte en línea para comenzar a recibir solicitudes.')
          else if (serviceTab == 0) ...[
            _DriverJobCard(kind: ServiceKind.ride, eta: '3 min', route: 'Av. Centro → Paitití', amount: 'Bs 5', onAccept: () => _accept(context, ServiceKind.ride)),
            const SizedBox(height: 10),
            _DriverJobCard(kind: ServiceKind.ride, eta: '5 min', route: 'Arroyo Chico → Centro', amount: 'Bs 7', onAccept: () => _accept(context, ServiceKind.ride)),
          ] else ...[
            _DriverJobCard(kind: ServiceKind.delivery, eta: '4 min', route: 'El Buen Sabor → Av. Paitití', amount: 'Bs 8', onAccept: () => _accept(context, ServiceKind.delivery)),
            const SizedBox(height: 10),
            _DriverJobCard(kind: ServiceKind.delivery, eta: '6 min', route: 'Farmacia Vida Salud → Calle 13', amount: 'Bs 10', onAccept: () => _accept(context, ServiceKind.delivery)),
          ],
        ],
      ),
    );
  }
}

class DriverActiveServicePage extends StatefulWidget {
  final ServiceKind kind;

  const DriverActiveServicePage({super.key, required this.kind});

  @override
  State<DriverActiveServicePage> createState() => _DriverActiveServicePageState();
}

class _DriverActiveServicePageState extends State<DriverActiveServicePage> {
  int stage = 0;

  @override
  Widget build(BuildContext context) {
    final ride = widget.kind == ServiceKind.ride;
    final rideLabels = ['Ir al pasajero', 'Pasajero a bordo', 'Completar viaje'];
    final deliveryLabels = ['Ir a recoger', 'Paquete recogido', 'Entregar paquete'];
    final labels = ride ? rideLabels : deliveryLabels;
    return Scaffold(
      appBar: AppBar(title: Text(ride ? 'Viaje en curso' : 'Delivery en curso')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _MapSurface(height: 330, car: ride),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Row(children: [
              CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(ride ? Icons.person_rounded : Icons.inventory_2_rounded, color: _blue)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ride ? 'Juan Pérez' : 'Paquete Express', style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(ride ? 'Av. Centro → Paitití' : 'El Buen Sabor → Av. Paitití', style: const TextStyle(color: _muted)),
              ])),
              IconButton(onPressed: () => _sheet(context, 'Contacto', 'Aquí se conectará llamada/chat protegido entre las partes.'), icon: const Icon(Icons.phone_rounded)),
            ]),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: labels[stage],
            icon: stage == 2 ? Icons.check_circle_rounded : Icons.navigation_rounded,
            accent: _yellow,
            foreground: _text,
            onPressed: () {
              if (stage < 2) {
                setState(() => stage += 1);
              } else {
                Navigator.pop(
                  context,
                  PreviewActivity(
                    kind: widget.kind,
                    title: ride ? 'Viaje completado por conductor' : 'Delivery completado por conductor',
                    route: ride ? 'Av. Centro → Paitití' : 'El Buen Sabor → Av. Paitití',
                    amount: ride ? 'Bs 5' : 'Bs 8',
                    status: 'Completado',
                    icon: ride ? Icons.local_taxi_rounded : Icons.local_shipping_rounded,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class EarningsPage extends StatelessWidget {
  const EarningsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const _TopBrand(role: 'Ganancias'),
          const SizedBox(height: 22),
          const Text('Mis ganancias', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [_blueDark, _blue]), borderRadius: BorderRadius.circular(24)),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total de hoy', style: TextStyle(color: Color(0xFFDCEAFF))),
              SizedBox(height: 4),
              Text('Bs 85', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900)),
              SizedBox(height: 8),
              Text('12 servicios completados', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 18),
          const _EarningLine(title: 'Viaje #125', amount: 'Bs 5', icon: Icons.local_taxi_rounded),
          const _EarningLine(title: 'Delivery #88', amount: 'Bs 8', icon: Icons.local_shipping_rounded),
          const _EarningLine(title: 'Viaje #124', amount: 'Bs 7', icon: Icons.local_taxi_rounded),
        ],
      ),
    );
  }
}

class _TopBrand extends StatelessWidget {
  final String role;
  const _TopBrand({required this.role});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 44, height: 44, decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 28)),
      const SizedBox(width: 10),
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('EXPRESS', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
        Text('Viajes · Delivery', style: TextStyle(color: _muted, fontSize: 11)),
      ]),
      const Spacer(),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(999)), child: Text(role, style: const TextStyle(color: _blue, fontSize: 11, fontWeight: FontWeight.w800))),
    ]);
  }
}

class _HeroServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String button;
  final Color accent;
  final VoidCallback onTap;

  const _HeroServiceCard({required this.icon, required this.title, required this.subtitle, required this.button, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE4E9F0)), boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 20, offset: Offset(0, 8))]),
      child: Row(children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(22)), child: Icon(icon, color: accent, size: 38)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: _muted, height: 1.35)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onTap, style: FilledButton.styleFrom(backgroundColor: accent), child: Text(button)),
        ])),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8), decoration: _cardDecoration(), child: Column(children: [Icon(icon, color: _blue), const SizedBox(height: 7), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))])),
      );
}

class _MiniActivity extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _MiniActivity({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14), decoration: _cardDecoration(), child: Row(children: [CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(icon, color: _blue)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12))])), const Icon(Icons.chevron_right_rounded, color: _muted)]));
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color accent;
  final Color foreground;

  const _PrimaryButton({required this.label, required this.icon, required this.onPressed, this.accent = _blue, this.foreground = Colors.white});

  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity, height: 54, child: FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)), style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: foreground, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))));
}

class _MapSurface extends StatelessWidget {
  final double height;
  final bool car;
  const _MapSurface({required this.height, required this.car});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFDCE3EC))),
        child: CustomPaint(
          painter: _MapPainter(),
          child: Stack(children: [
            const Positioned(left: 24, bottom: 28, child: _MapPin(color: Color(0xFF12B76A), icon: Icons.my_location_rounded)),
            const Positioned(right: 30, top: 32, child: _MapPin(color: Color(0xFFF04438), icon: Icons.location_on_rounded)),
            Positioned(left: 0, right: 0, top: height * .42, child: Center(child: Container(width: 42, height: 42, decoration: BoxDecoration(color: car ? _yellow : _blue, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12)]), child: Icon(car ? Icons.local_taxi_rounded : Icons.local_shipping_rounded, color: car ? _text : Colors.white, size: 24)))),
          ]),
        ),
      );
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFEFF3F7);
    canvas.drawRect(Offset.zero & size, bg);
    final road = Paint()..color = Colors.white..strokeWidth = 14..style = PaintingStyle.stroke;
    for (int i = -2; i < 7; i++) {
      final y = i * 60.0 + 20;
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 70), road);
    }
    for (int i = -1; i < 6; i++) {
      final x = i * 85.0 + 25;
      canvas.drawLine(Offset(x, 0), Offset(x + 45, size.height), road);
    }
    final route = Paint()..color = _blue..strokeWidth = 5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(36, size.height - 40)..cubicTo(size.width * .35, size.height * .7, size.width * .48, size.height * .55, size.width * .55, size.height * .48)..cubicTo(size.width * .75, size.height * .34, size.width * .82, size.height * .28, size.width - 42, 48);
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapPin extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _MapPin({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(width: 42, height: 42, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)]), child: Icon(icon, color: Colors.white, size: 21));
}

class _DriverCard extends StatelessWidget {
  final bool delivery;
  const _DriverCard({this.delivery = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Row(children: [
          const CircleAvatar(radius: 26, backgroundColor: Color(0xFFEAF2FF), child: Icon(Icons.person_rounded, color: _blue)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(delivery ? 'Ana Torres' : 'Carlos Mendoza', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text(delivery ? '★ 4.8 · Moto · 5GY8VZ' : '★ 4.9 · Toyota Corolla · 123ABC', style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 4),
            const Text('Llegada estimada: 3 min', style: TextStyle(color: _blue, fontWeight: FontWeight.w700, fontSize: 12)),
          ])),
          IconButton(onPressed: () => _sheet(context, 'Contacto', 'Aquí se conectará llamada o chat protegido.'), icon: const Icon(Icons.phone_rounded)),
        ]),
      );
}

class _TripInfoCard extends StatelessWidget {
  const _TripInfoCard();

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: _cardDecoration(), child: const Column(children: [
        _InfoLine(icon: Icons.location_on_outlined, label: 'Destino', value: 'Av. Paitití'),
        Divider(height: 24),
        _InfoLine(icon: Icons.schedule_rounded, label: 'Tiempo restante', value: '12 min'),
        Divider(height: 24),
        _InfoLine(icon: Icons.route_rounded, label: 'Distancia', value: '4.2 km'),
      ]));
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoLine({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, color: _blue), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(color: _muted))), Text(value, style: const TextStyle(fontWeight: FontWeight.w800))]);
}

class _StatusPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  const _StatusPanel({required this.icon, required this.title, required this.subtitle, required this.trailing});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: _cardDecoration(), child: Row(children: [CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(icon, color: _blue)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12))])), trailing]));
}

class _RatingSheet extends StatefulWidget {
  const _RatingSheet();
  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int rating = 5;
  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(22, 6, 22, 28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('¿Cómo fue tu viaje?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Carlos Mendoza', style: TextStyle(color: _muted)),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => IconButton(onPressed: () => setState(() => rating = i + 1), icon: Icon(i < rating ? Icons.star_rounded : Icons.star_outline_rounded, color: _yellow, size: 38)))),
        const SizedBox(height: 12),
        _PrimaryButton(label: 'Enviar calificación', icon: Icons.send_rounded, onPressed: () => Navigator.pop(context, rating)),
      ])));
}

class _PackageChoice extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PackageChoice({required this.selected, required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? _blue : const Color(0xFFD9E0EA), width: selected ? 2 : 1)), child: Column(children: [Icon(icon, color: selected ? _blue : _muted), const SizedBox(height: 7), Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? _blue : _text, fontSize: 12))])));
}

class _RouteSummary extends StatelessWidget {
  final String from;
  final String to;
  const _RouteSummary({required this.from, required this.to});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: _cardDecoration(), child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.trip_origin_rounded, color: Color(0xFF12B76A)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Recogida', style: TextStyle(color: _muted, fontSize: 12)), Text(from, style: const TextStyle(fontWeight: FontWeight.w800))]))]),
        const Padding(padding: EdgeInsets.only(left: 11), child: Align(alignment: Alignment.centerLeft, child: SizedBox(height: 18, child: VerticalDivider(width: 1)))),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.location_on_rounded, color: Color(0xFFF04438)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Entrega', style: TextStyle(color: _muted, fontSize: 12)), Text(to, style: const TextStyle(fontWeight: FontWeight.w800))]))]),
      ]));
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  const _PriceRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: _muted))), Text(value, style: const TextStyle(fontWeight: FontWeight.w900))]));
}

class _TimelineStep extends StatelessWidget {
  final String label;
  final bool done;
  final bool last;
  const _TimelineStep({required this.label, required this.done, required this.last});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [Container(width: 28, height: 28, decoration: BoxDecoration(color: done ? _blue : const Color(0xFFE4E7EC), shape: BoxShape.circle), child: Icon(done ? Icons.check_rounded : Icons.more_horiz_rounded, color: done ? Colors.white : _muted, size: 17)), if (!last) Container(width: 2, height: 34, color: done ? _blue : const Color(0xFFE4E7EC))]),
        const SizedBox(width: 12),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(label, style: TextStyle(fontWeight: done ? FontWeight.w800 : FontWeight.w500, color: done ? _text : _muted))),
      ]);
}

class _PaymentTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  const _PaymentTile({required this.icon, required this.title, required this.subtitle, required this.trailing});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(15), decoration: _cardDecoration(), child: Row(children: [CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(icon, color: _blue)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12))])), Text(trailing, style: const TextStyle(color: _blue, fontWeight: FontWeight.w800))]));
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool highlight;
  const _SettingsTile({required this.icon, required this.title, required this.onTap, this.highlight = false});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: ListTile(onTap: onTap, tileColor: highlight ? const Color(0xFFEAF2FF) : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: highlight ? const Color(0xFFB9D4FF) : const Color(0xFFE4E9F0))), leading: Icon(icon, color: highlight ? _blue : _text), title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: highlight ? _blue : _text)), trailing: const Icon(Icons.chevron_right_rounded)));
}

class _DriverMetric extends StatelessWidget {
  final String label;
  final String value;
  const _DriverMetric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .13), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .16))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: Color(0xFFDCEAFF), fontSize: 12))]));
}

class _DriverJobCard extends StatelessWidget {
  final ServiceKind kind;
  final String eta;
  final String route;
  final String amount;
  final VoidCallback onAccept;
  const _DriverJobCard({required this.kind, required this.eta, required this.route, required this.amount, required this.onAccept});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: _cardDecoration(), child: Column(children: [
        Row(children: [CircleAvatar(backgroundColor: kind == ServiceKind.ride ? const Color(0xFFFFF4CC) : const Color(0xFFEAF2FF), child: Icon(kind == ServiceKind.ride ? Icons.local_taxi_rounded : Icons.local_shipping_rounded, color: kind == ServiceKind.ride ? const Color(0xFF9A6700) : _blue)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(route, style: const TextStyle(fontWeight: FontWeight.w900)), Text('Recogida en $eta', style: const TextStyle(color: _muted, fontSize: 12))])), Text(amount, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))]),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: onAccept, style: FilledButton.styleFrom(backgroundColor: _yellow, foregroundColor: _text), child: const Text('Aceptar', style: TextStyle(fontWeight: FontWeight.w900)))),
      ]));
}

class _EarningLine extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  const _EarningLine({required this.title, required this.amount, required this.icon});
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(15), decoration: _cardDecoration(), child: Row(children: [CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(icon, color: _blue)), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(amount, style: const TextStyle(fontWeight: FontWeight.w900))]));
}

class _InfoStrip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoStrip({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(16)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: _blue, size: 20), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(color: _blueDark, height: 1.35, fontSize: 13)))]));
}

BoxDecoration _cardDecoration() => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE4E9F0)));

void _sheet(BuildContext context, String title, String body) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(22, 4, 22, 30), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 10), Text(body, style: const TextStyle(color: _muted, height: 1.5))]))),
  );
}

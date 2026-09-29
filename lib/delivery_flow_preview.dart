import 'package:flutter/material.dart';

enum DeliveryPreviewStage { idle, requested, accepted, pickingUp, inTransit, delivered }
enum DeliveryPreviewRole { customer, courier }

const _blue = Color(0xFF0B57D0);
const _blueDark = Color(0xFF073B8C);
const _bg = Color(0xFFF5F7FB);
const _text = Color(0xFF101828);
const _muted = Color(0xFF667085);
const _green = Color(0xFF12B76A);
const _red = Color(0xFFF04438);

class DeliveryFlowPreviewPage extends StatefulWidget {
  final VoidCallback onClose;

  const DeliveryFlowPreviewPage({super.key, required this.onClose});

  @override
  State<DeliveryFlowPreviewPage> createState() => _DeliveryFlowPreviewPageState();
}

class _DeliveryFlowPreviewPageState extends State<DeliveryFlowPreviewPage> {
  DeliveryPreviewRole role = DeliveryPreviewRole.customer;
  DeliveryPreviewStage stage = DeliveryPreviewStage.idle;
  int packageType = 1;
  int payment = 0;
  int rating = 0;

  final pickup = TextEditingController(text: 'Av. 6 de Agosto');
  final dropoff = TextEditingController(text: 'Calle Paitití');
  final details = TextEditingController(text: 'Caja pequeña, frágil');

  final packageTypes = const [
    ('Documento', Icons.description_outlined),
    ('Paquete', Icons.inventory_2_outlined),
    ('Compra', Icons.shopping_bag_outlined),
  ];

  @override
  void dispose() {
    pickup.dispose();
    dropoff.dispose();
    details.dispose();
    super.dispose();
  }

  String get stageLabel => switch (stage) {
        DeliveryPreviewStage.idle => 'Sin envío activo',
        DeliveryPreviewStage.requested => 'Buscando repartidor',
        DeliveryPreviewStage.accepted => 'Repartidor asignado',
        DeliveryPreviewStage.pickingUp => 'Recogiendo paquete',
        DeliveryPreviewStage.inTransit => 'En camino al destino',
        DeliveryPreviewStage.delivered => 'Entrega completada',
      };

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
            borderSide: const BorderSide(color: _blue, width: 1.5),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Express · Delivery'),
          leading: IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 48),
            children: [
              _hero(),
              const SizedBox(height: 14),
              _roleSwitcher(),
              const SizedBox(height: 14),
              _sharedStatus(),
              const SizedBox(height: 14),
              _map(),
              const SizedBox(height: 14),
              role == DeliveryPreviewRole.customer ? _customerView() : _courierView(),
              const SizedBox(height: 14),
              _timeline(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_blueDark, _blue]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EXPRESS · DELIVERY',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.1),
            ),
            SizedBox(height: 8),
            Text(
              'Un envío, dos vistas sincronizadas',
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.08),
            ),
            SizedBox(height: 8),
            Text(
              'Crea el envío como cliente y cambia a repartidor para aceptar, recoger, trasladar y completar la entrega.',
              style: TextStyle(color: Color(0xFFDCEAFF), height: 1.45),
            ),
          ],
        ),
      );

  Widget _roleSwitcher() => Row(
        children: [
          Expanded(
            child: _roleCard(
              label: 'Cliente',
              icon: Icons.person_rounded,
              selected: role == DeliveryPreviewRole.customer,
              onTap: () => setState(() => role = DeliveryPreviewRole.customer),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _roleCard(
              label: 'Repartidor',
              icon: Icons.delivery_dining_rounded,
              selected: role == DeliveryPreviewRole.courier,
              onTap: () => setState(() => role = DeliveryPreviewRole.courier),
            ),
          ),
        ],
      );

  Widget _roleCard({required String label, required IconData icon, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _blue : const Color(0xFFE4E9F0), width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: _blue),
            const SizedBox(width: 9),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))),
            if (selected) const Icon(Icons.check_circle_rounded, color: _blue),
          ],
        ),
      ),
    );
  }

  Widget _sharedStatus() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.sync_rounded, color: _blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estado compartido', style: TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(stageLabel, style: const TextStyle(color: _text, fontSize: 19, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const Text('Bs 8', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ],
        ),
      );

  Widget _map() => Container(
        height: 245,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDCE3EC)),
        ),
        child: CustomPaint(
          painter: _DeliveryMapPainter(),
          child: Stack(
            children: [
              const Positioned(left: 28, bottom: 28, child: _MapDot(color: _green, icon: Icons.inventory_2_rounded)),
              const Positioned(right: 30, top: 26, child: _MapDot(color: _red, icon: Icons.location_on_rounded)),
              if (stage.index >= DeliveryPreviewStage.accepted.index && stage != DeliveryPreviewStage.delivered)
                Positioned(
                  left: stage == DeliveryPreviewStage.inTransit ? null : 118,
                  right: stage == DeliveryPreviewStage.inTransit ? 90 : null,
                  top: stage == DeliveryPreviewStage.inTransit ? 80 : 132,
                  child: const _MapDot(color: Color(0xFFFFC928), icon: Icons.delivery_dining_rounded, darkIcon: true),
                ),
            ],
          ),
        ),
      );

  Widget _customerView() {
    switch (stage) {
      case DeliveryPreviewStage.idle:
        return Column(
          children: [
            _deliveryForm(),
            const SizedBox(height: 12),
            _paymentCard(),
            const SizedBox(height: 12),
            _actionCard(
              title: 'Resumen del envío',
              subtitle: '${packageTypes[packageType].$1} · Recogida estimada 5 min · Tarifa Bs 8',
              button: 'Solicitar repartidor · Bs 8',
              icon: Icons.local_shipping_rounded,
              onPressed: () => setState(() => stage = DeliveryPreviewStage.requested),
            ),
          ],
        );
      case DeliveryPreviewStage.requested:
        return _statusCard('Buscando repartidor cercano', 'Tu solicitud ya está visible para repartidores disponibles.', Icons.radar_rounded);
      case DeliveryPreviewStage.accepted:
        return Column(
          children: [
            _courierCard(),
            const SizedBox(height: 12),
            _contactActions(),
            const SizedBox(height: 12),
            _statusCard('Marco aceptó tu envío', 'Honda Navi · DEL-204 · ★ 4.9 · Llegada estimada 4 min', Icons.delivery_dining_rounded),
          ],
        );
      case DeliveryPreviewStage.pickingUp:
        return Column(
          children: [
            _courierCard(),
            const SizedBox(height: 12),
            _contactActions(),
            const SizedBox(height: 12),
            _statusCard('Recogiendo el paquete', 'El repartidor está en el punto de origen verificando el envío.', Icons.inventory_2_rounded),
            const SizedBox(height: 12),
            _securityCard(),
          ],
        );
      case DeliveryPreviewStage.inTransit:
        return Column(
          children: [
            _courierCard(),
            const SizedBox(height: 12),
            _contactActions(),
            const SizedBox(height: 12),
            _statusCard('Tu envío va en camino', 'Destino: Calle Paitití · 9 min restantes', Icons.route_rounded),
            const SizedBox(height: 12),
            _securityCard(),
          ],
        );
      case DeliveryPreviewStage.delivered:
        return Column(
          children: [
            _statusCard('Entrega completada', 'El paquete fue marcado como entregado. Total: Bs 8.', Icons.check_circle_rounded),
            const SizedBox(height: 12),
            _ratingCard(),
            const SizedBox(height: 12),
            _actionCard(
              title: '¿Necesitas otro envío?',
              subtitle: 'Puedes reiniciar este preview y crear una nueva solicitud.',
              button: 'Crear otro envío',
              icon: Icons.refresh_rounded,
              onPressed: () => setState(() {
                stage = DeliveryPreviewStage.idle;
                rating = 0;
              }),
            ),
          ],
        );
    }
  }

  Widget _courierView() {
    switch (stage) {
      case DeliveryPreviewStage.idle:
        return _statusCard('Sin solicitudes activas', 'Cambia a Cliente y crea un envío para verlo aparecer aquí.', Icons.inbox_outlined);
      case DeliveryPreviewStage.requested:
        return _actionCard(
          title: 'Nueva solicitud de Delivery',
          subtitle: 'Av. 6 de Agosto → Calle Paitití · ${packageTypes[packageType].$1} · Bs 8',
          button: 'Aceptar envío',
          icon: Icons.notifications_active_rounded,
          onPressed: () => setState(() => stage = DeliveryPreviewStage.accepted),
        );
      case DeliveryPreviewStage.accepted:
        return Column(
          children: [
            _customerCard(),
            const SizedBox(height: 12),
            _actionCard(
              title: 'Envío aceptado',
              subtitle: 'Dirígete al punto de recogida y confirma cuando tengas el paquete.',
              button: 'Llegué a recoger',
              icon: Icons.navigation_rounded,
              onPressed: () => setState(() => stage = DeliveryPreviewStage.pickingUp),
            ),
          ],
        );
      case DeliveryPreviewStage.pickingUp:
        return Column(
          children: [
            _customerCard(),
            const SizedBox(height: 12),
            _actionCard(
              title: 'Paquete verificado',
              subtitle: '${packageTypes[packageType].$1} · ${details.text}',
              button: 'Iniciar entrega',
              icon: Icons.inventory_2_rounded,
              onPressed: () => setState(() => stage = DeliveryPreviewStage.inTransit),
            ),
          ],
        );
      case DeliveryPreviewStage.inTransit:
        return Column(
          children: [
            _customerCard(),
            const SizedBox(height: 12),
            _actionCard(
              title: 'Entrega en curso',
              subtitle: 'Sigue la ruta hasta Calle Paitití. El cliente ve tu progreso en tiempo real.',
              button: 'Marcar como entregado',
              icon: Icons.flag_rounded,
              onPressed: () => setState(() => stage = DeliveryPreviewStage.delivered),
            ),
            const SizedBox(height: 12),
            _securityCard(),
          ],
        );
      case DeliveryPreviewStage.delivered:
        return _statusCard('Servicio completado', 'El cliente ya ve la entrega finalizada y puede calificarte.', Icons.check_circle_rounded);
    }
  }

  Widget _deliveryForm() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Datos del envío', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(controller: pickup, decoration: const InputDecoration(labelText: 'Dirección de recogida', prefixIcon: Icon(Icons.trip_origin_rounded))),
            const SizedBox(height: 10),
            TextField(controller: dropoff, decoration: const InputDecoration(labelText: 'Dirección de entrega', prefixIcon: Icon(Icons.location_on_rounded))),
            const SizedBox(height: 14),
            const Text('¿Qué vas a enviar?', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: List.generate(packageTypes.length, (i) {
                final item = packageTypes[i];
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == packageTypes.length - 1 ? 0 : 8),
                    child: InkWell(
                      onTap: () => setState(() => packageType = i),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        decoration: BoxDecoration(
                          color: packageType == i ? const Color(0xFFEAF2FF) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: packageType == i ? _blue : const Color(0xFFE4E9F0), width: packageType == i ? 2 : 1),
                        ),
                        child: Column(
                          children: [
                            Icon(item.$2, color: _blue),
                            const SizedBox(height: 6),
                            Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12), textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(controller: details, maxLines: 2, decoration: const InputDecoration(labelText: 'Detalles del paquete', prefixIcon: Icon(Icons.edit_note_rounded))),
          ],
        ),
      );

  Widget _paymentCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Forma de pago', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            _paymentOption(0, Icons.payments_outlined, 'Efectivo', 'Pagar al finalizar'),
            const SizedBox(height: 8),
            _paymentOption(1, Icons.credit_card_rounded, 'Tarjeta', 'Visa •••• 4242'),
            const SizedBox(height: 8),
            _paymentOption(2, Icons.account_balance_wallet_outlined, 'Billetera Express', 'Saldo Bs 42'),
          ],
        ),
      );

  Widget _paymentOption(int index, IconData icon, String title, String subtitle) {
    final selected = payment == index;
    return InkWell(
      onTap: () => setState(() => payment = index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _blue : const Color(0xFFE4E9F0)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _blue),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12))])),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? _blue : _muted),
          ],
        ),
      ),
    );
  }

  Widget _courierCard() => _personCard(
        icon: Icons.delivery_dining_rounded,
        title: 'Marco Rojas',
        subtitle: 'Honda Navi · DEL-204 · ★ 4.9',
      );

  Widget _customerCard() => _personCard(
        icon: Icons.person_rounded,
        title: 'Juan Pérez',
        subtitle: 'Cliente · Recogida en Av. 6 de Agosto',
      );

  Widget _personCard({required IconData icon, required String title, required String subtitle}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Row(
          children: [
            CircleAvatar(radius: 24, backgroundColor: const Color(0xFFEAF2FF), child: Icon(icon, color: _blue)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), Text(subtitle, style: const TextStyle(color: _muted))])),
          ],
        ),
      );

  Widget _contactActions() => Row(
        children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => _showInfo('Llamada', 'Aquí se abriría la llamada protegida entre cliente y repartidor.'), icon: const Icon(Icons.call_outlined), label: const Text('Llamar'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: () => _showInfo('Chat', 'Aquí se abriría el chat del envío activo.'), icon: const Icon(Icons.chat_bubble_outline_rounded), label: const Text('Chat'))),
        ],
      );

  Widget _securityCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.shield_rounded, color: _blue), SizedBox(width: 9), Text('Seguridad del envío', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))]),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _showInfo('Compartir seguimiento', 'Se compartiría el enlace y estado del envío con un contacto de confianza.'), icon: const Icon(Icons.share_location_outlined), label: const Text('Compartir'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _red), onPressed: () => _showInfo('SOS', 'El botón SOS avisaría a los contactos definidos y enviaría la ubicación del servicio activo.'), icon: const Icon(Icons.sos_rounded), label: const Text('SOS'))),
              ],
            ),
          ],
        ),
      );

  Widget _ratingCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          children: [
            const Text('Califica a tu repartidor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => IconButton(
                    onPressed: () => setState(() => rating = i + 1),
                    icon: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFFFA800), size: 34),
                  )),
            ),
            Text(rating == 0 ? 'Toca una estrella' : '$rating de 5 estrellas', style: const TextStyle(color: _muted)),
          ],
        ),
      );

  Widget _actionCard({required String title, required String subtitle, required String button, required IconData icon, required VoidCallback onPressed}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, color: _blue), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: _muted, height: 1.4)),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: onPressed, child: Text(button, style: const TextStyle(fontWeight: FontWeight.w800)))),
          ],
        ),
      );

  Widget _statusCard(String title, String subtitle, IconData icon) => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(icon, color: _blue)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: _muted, height: 1.35))])),
          ],
        ),
      );

  Widget _timeline() {
    final steps = const [
      ('Solicitud', DeliveryPreviewStage.requested),
      ('Aceptado', DeliveryPreviewStage.accepted),
      ('Recogida', DeliveryPreviewStage.pickingUp),
      ('En camino', DeliveryPreviewStage.inTransit),
      ('Entregado', DeliveryPreviewStage.delivered),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Seguimiento del envío', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...steps.map((step) {
            final done = stage.index >= step.$2.index;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? _blue : const Color(0xFF98A2B3), size: 20),
                  const SizedBox(width: 10),
                  Text(step.$1, style: TextStyle(fontWeight: done ? FontWeight.w800 : FontWeight.w500, color: done ? _text : _muted)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _showInfo(String title, String message) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(message, style: const TextStyle(color: _muted, height: 1.5)),
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))),
            ],
          ),
        ),
      );

  BoxDecoration _card() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9F0)),
      );
}

class _MapDot extends StatelessWidget {
  final Color color;
  final IconData icon;
  final bool darkIcon;

  const _MapDot({required this.color, required this.icon, this.darkIcon = false});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
        ),
        child: Icon(icon, color: darkIcon ? _text : Colors.white, size: 22),
      );
}

class _DeliveryMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEFF3F7));
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke;
    for (int i = -2; i < 7; i++) {
      final y = i * 58.0 + 18;
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 66), road);
    }
    for (int i = -1; i < 6; i++) {
      final x = i * 82.0 + 20;
      canvas.drawLine(Offset(x, 0), Offset(x + 48, size.height), road);
    }
    final route = Paint()
      ..color = _blue
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(48, size.height - 48)
      ..cubicTo(size.width * .32, size.height * .58, size.width * .60, size.height * .62, size.width - 52, 52);
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

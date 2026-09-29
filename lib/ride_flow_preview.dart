import 'package:flutter/material.dart';

enum RidePreviewStage { idle, requested, accepted, arriving, inProgress, completed }
enum RidePreviewRole { customer, driver }

const _blue = Color(0xFF0B57D0);
const _blueDark = Color(0xFF073B8C);
const _yellow = Color(0xFFFFC928);
const _bg = Color(0xFFF5F7FB);
const _text = Color(0xFF101828);
const _muted = Color(0xFF667085);
const _green = Color(0xFF12B76A);
const _red = Color(0xFFF04438);

class RideFlowPreviewPage extends StatefulWidget {
  final VoidCallback onClose;

  const RideFlowPreviewPage({super.key, required this.onClose});

  @override
  State<RideFlowPreviewPage> createState() => _RideFlowPreviewPageState();
}

class _RideFlowPreviewPageState extends State<RideFlowPreviewPage> {
  RidePreviewRole role = RidePreviewRole.customer;
  RidePreviewStage stage = RidePreviewStage.idle;
  int vehicle = 0;
  int payment = 0;
  int rating = 0;

  final from = TextEditingController(text: 'Mi ubicación actual');
  final to = TextEditingController(text: 'Av. Paitití');

  final vehicles = const [
    ('Express', 'Bs 5', '3 min', Icons.directions_car_filled_rounded),
    ('Comfort', 'Bs 7', '4 min', Icons.local_taxi_rounded),
    ('XL', 'Bs 10', '5 min', Icons.airport_shuttle_rounded),
  ];

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  String get stageLabel => switch (stage) {
        RidePreviewStage.idle => 'Sin viaje activo',
        RidePreviewStage.requested => 'Buscando conductor',
        RidePreviewStage.accepted => 'Conductor asignado',
        RidePreviewStage.arriving => 'Conductor en camino',
        RidePreviewStage.inProgress => 'Viaje en curso',
        RidePreviewStage.completed => 'Viaje completado',
      };

  String get selectedPrice => vehicles[vehicle].$2;

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
          title: const Text('Express · Viajes'),
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
              role == RidePreviewRole.customer ? _customerView() : _driverView(),
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
            Text('EXPRESS · VIAJES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.1)),
            SizedBox(height: 8),
            Text('Cliente y conductor conectados en un mismo servicio', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, height: 1.08)),
            SizedBox(height: 8),
            Text('Prueba el viaje completo, desde la solicitud hasta la calificación final.', style: TextStyle(color: Color(0xFFDCEAFF), height: 1.45)),
          ],
        ),
      );

  Widget _roleSwitcher() => Row(
        children: [
          Expanded(child: _roleButton(RidePreviewRole.customer, 'Cliente', Icons.person_rounded)),
          const SizedBox(width: 10),
          Expanded(child: _roleButton(RidePreviewRole.driver, 'Conductor', Icons.local_taxi_rounded)),
        ],
      );

  Widget _roleButton(RidePreviewRole value, String label, IconData icon) {
    final selected = role == value;
    return InkWell(
      onTap: () => setState(() => role = value),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _blue : const Color(0xFFE4E9F0), width: selected ? 2 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _blue),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _sharedStatus() => Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.sync_rounded, color: _blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estado compartido', style: TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(stageLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            if (stage != RidePreviewStage.idle)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(999)),
                child: Text(selectedPrice, style: const TextStyle(color: _blue, fontWeight: FontWeight.w900, fontSize: 12)),
              ),
          ],
        ),
      );

  Widget _map() => Container(
        height: 245,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFDCE3EC))),
        child: CustomPaint(
          painter: _RideMapPainter(),
          child: Stack(
            children: [
              const Positioned(left: 26, bottom: 28, child: _MapDot(color: _green, icon: Icons.person_rounded)),
              const Positioned(right: 30, top: 26, child: _MapDot(color: _red, icon: Icons.location_on_rounded)),
              if (stage.index >= RidePreviewStage.accepted.index && stage != RidePreviewStage.completed)
                Positioned(
                  left: 0,
                  right: 0,
                  top: stage == RidePreviewStage.inProgress ? 88 : 126,
                  child: const Center(child: _MapDot(color: _yellow, icon: Icons.local_taxi_rounded, darkIcon: true)),
                ),
            ],
          ),
        ),
      );

  Widget _customerView() {
    switch (stage) {
      case RidePreviewStage.idle:
        return _customerRequest();
      case RidePreviewStage.requested:
        return Column(children: [
          _statusCard('Buscando conductor cercano', 'Estamos enviando tu solicitud a conductores disponibles.', Icons.radar_rounded),
          const SizedBox(height: 10),
          _secondaryButton('Cancelar solicitud', Icons.close_rounded, () => setState(() => stage = RidePreviewStage.idle)),
        ]);
      case RidePreviewStage.accepted:
      case RidePreviewStage.arriving:
        return Column(children: [
          _driverCard(),
          const SizedBox(height: 10),
          _tripSummary(),
          const SizedBox(height: 10),
          _safetyActions(),
        ]);
      case RidePreviewStage.inProgress:
        return Column(children: [
          _driverCard(),
          const SizedBox(height: 10),
          _tripSummary(),
          const SizedBox(height: 10),
          _safetyActions(),
        ]);
      case RidePreviewStage.completed:
        return _completedCustomer();
    }
  }

  Widget _customerRequest() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Solicitar viaje', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(controller: from, decoration: const InputDecoration(labelText: 'Punto de partida', prefixIcon: Icon(Icons.my_location_rounded))),
            const SizedBox(height: 10),
            TextField(controller: to, decoration: const InputDecoration(labelText: 'Destino', prefixIcon: Icon(Icons.location_on_rounded))),
            const SizedBox(height: 16),
            const Text('Elige tu vehículo', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            ...List.generate(vehicles.length, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _vehicleTile(i),
                )),
            const SizedBox(height: 8),
            const Text('Forma de pago', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _paymentChoice(0, 'Efectivo', Icons.payments_outlined)),
                const SizedBox(width: 10),
                Expanded(child: _paymentChoice(1, 'Tarjeta', Icons.credit_card_rounded)),
              ],
            ),
            const SizedBox(height: 14),
            _primaryButton('Solicitar ${vehicles[vehicle].$1} · $selectedPrice', Icons.local_taxi_rounded, () => setState(() => stage = RidePreviewStage.requested)),
          ],
        ),
      );

  Widget _vehicleTile(int i) {
    final item = vehicles[i];
    final selected = vehicle == i;
    return InkWell(
      onTap: () => setState(() => vehicle = i),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF7FAFF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _blue : const Color(0xFFE4E9F0), width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(item.$4, color: _blue)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w900)), Text('${item.$3} de llegada', style: const TextStyle(color: _muted, fontSize: 12))])),
            Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ],
        ),
      ),
    );
  }

  Widget _paymentChoice(int value, String label, IconData icon) {
    final selected = payment == value;
    return InkWell(
      onTap: () => setState(() => payment = value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _blue : const Color(0xFFE4E9F0)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: _blue, size: 20), const SizedBox(width: 7), Text(label, style: const TextStyle(fontWeight: FontWeight.w800))]),
      ),
    );
  }

  Widget _driverView() {
    switch (stage) {
      case RidePreviewStage.idle:
        return _statusCard('Sin solicitudes activas', 'Cambia a Cliente y crea un viaje para verlo aparecer aquí.', Icons.inbox_outlined);
      case RidePreviewStage.requested:
        return _driverIncoming();
      case RidePreviewStage.accepted:
        return Column(children: [
          _passengerCard(),
          const SizedBox(height: 10),
          _primaryButton('Voy al pasajero', Icons.navigation_rounded, () => setState(() => stage = RidePreviewStage.arriving), accent: _yellow, foreground: _text),
        ]);
      case RidePreviewStage.arriving:
        return Column(children: [
          _passengerCard(),
          const SizedBox(height: 10),
          _primaryButton('Pasajero a bordo', Icons.person_add_alt_1_rounded, () => setState(() => stage = RidePreviewStage.inProgress), accent: _yellow, foreground: _text),
        ]);
      case RidePreviewStage.inProgress:
        return Column(children: [
          _passengerCard(),
          const SizedBox(height: 10),
          _tripSummary(),
          const SizedBox(height: 10),
          _primaryButton('Completar viaje', Icons.flag_rounded, () => setState(() => stage = RidePreviewStage.completed), accent: _yellow, foreground: _text),
        ]);
      case RidePreviewStage.completed:
        return _statusCard('Servicio completado', 'El viaje ya aparece completado también para el cliente.', Icons.check_circle_rounded);
    }
  }

  Widget _driverIncoming() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [CircleAvatar(backgroundColor: Color(0xFFFFF4CC), child: Icon(Icons.local_taxi_rounded, color: Color(0xFF9A6700))), SizedBox(width: 10), Expanded(child: Text('Nueva solicitud', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))), Text('Bs 5', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18))]),
            const SizedBox(height: 12),
            _infoLine(Icons.trip_origin_rounded, 'Recogida', 'Mi ubicación actual'),
            const Divider(height: 22),
            _infoLine(Icons.location_on_rounded, 'Destino', 'Av. Paitití'),
            const Divider(height: 22),
            _infoLine(Icons.schedule_rounded, 'Llegada a recogida', '3 min'),
            const SizedBox(height: 14),
            _primaryButton('Aceptar viaje', Icons.check_rounded, () => setState(() => stage = RidePreviewStage.accepted), accent: _yellow, foreground: _text),
          ],
        ),
      );

  Widget _driverCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Row(
          children: [
            const CircleAvatar(radius: 26, backgroundColor: Color(0xFFEAF2FF), child: Icon(Icons.person_rounded, color: _blue)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Carlos Mendoza', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text('★ 4.9 · Toyota Corolla · 123ABC', style: TextStyle(color: _muted, fontSize: 12)), SizedBox(height: 3), Text('Llegada estimada: 3 min', style: TextStyle(color: _blue, fontWeight: FontWeight.w700, fontSize: 12))])),
            IconButton(onPressed: () => _sheet('Llamar al conductor', 'Aquí se conectará una llamada protegida sin exponer información innecesaria.'), icon: const Icon(Icons.phone_rounded)),
            IconButton(onPressed: () => _sheet('Chat', 'Aquí se conectará el chat en tiempo real entre cliente y conductor.'), icon: const Icon(Icons.chat_bubble_outline_rounded)),
          ],
        ),
      );

  Widget _passengerCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Row(
          children: [
            const CircleAvatar(radius: 25, backgroundColor: Color(0xFFEAF2FF), child: Icon(Icons.person_rounded, color: _blue)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Juan Pérez', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text('Cliente · ★ 4.9', style: TextStyle(color: _muted, fontSize: 12))])),
            IconButton(onPressed: () => _sheet('Llamar al cliente', 'Aquí se conectará una llamada protegida con el cliente.'), icon: const Icon(Icons.phone_rounded)),
            IconButton(onPressed: () => _sheet('Chat', 'Aquí se conectará el chat en tiempo real con el cliente.'), icon: const Icon(Icons.chat_bubble_outline_rounded)),
          ],
        ),
      );

  Widget _tripSummary() => Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Column(
          children: [
            _infoLine(Icons.location_on_outlined, 'Destino', to.text),
            const Divider(height: 22),
            _infoLine(Icons.schedule_rounded, 'Tiempo estimado', stage == RidePreviewStage.inProgress ? '12 min restantes' : '15 min'),
            const Divider(height: 22),
            _infoLine(Icons.route_rounded, 'Distancia', '4.2 km'),
            const Divider(height: 22),
            _infoLine(payment == 0 ? Icons.payments_outlined : Icons.credit_card_rounded, 'Pago', payment == 0 ? 'Efectivo · $selectedPrice' : 'Tarjeta · $selectedPrice'),
          ],
        ),
      );

  Widget _safetyActions() => Row(
        children: [
          Expanded(child: _quickAction(Icons.share_location_rounded, 'Compartir', () => _sheet('Compartir viaje', 'Se compartirá el seguimiento del servicio con un contacto de confianza.'))),
          const SizedBox(width: 10),
          Expanded(child: _quickAction(Icons.shield_outlined, 'Seguridad', () => _sheet('Seguridad', 'Botón de pánico, contactos de confianza y datos del servicio estarán disponibles aquí.'))),
          const SizedBox(width: 10),
          Expanded(child: _quickAction(Icons.sos_rounded, 'SOS', () => _sheet('Botón de pánico', 'Esta acción enviará la ubicación y los datos del viaje al flujo de emergencia configurado.'))),
        ],
      );

  Widget _completedCustomer() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          children: [
            const Icon(Icons.check_circle_rounded, size: 58, color: _green),
            const SizedBox(height: 10),
            const Text('Viaje completado', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text('Total $selectedPrice · ${payment == 0 ? 'Efectivo' : 'Tarjeta'}', style: const TextStyle(color: _muted)),
            const SizedBox(height: 14),
            const Text('Califica tu viaje', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => IconButton(
                    onPressed: () => setState(() => rating = i + 1),
                    icon: Icon(i < rating ? Icons.star_rounded : Icons.star_outline_rounded, color: _yellow, size: 34),
                  )),
            ),
            const SizedBox(height: 10),
            _primaryButton('Crear otro viaje', Icons.refresh_rounded, () => setState(() {
                  stage = RidePreviewStage.idle;
                  rating = 0;
                })),
          ],
        ),
      );

  Widget _timeline() {
    final steps = const [
      ('Solicitud enviada', RidePreviewStage.requested),
      ('Conductor asignado', RidePreviewStage.accepted),
      ('Conductor en camino', RidePreviewStage.arriving),
      ('Viaje iniciado', RidePreviewStage.inProgress),
      ('Viaje completado', RidePreviewStage.completed),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Seguimiento del servicio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...steps.map((step) {
            final done = stage.index >= step.$2.index;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? _blue : const Color(0xFF98A2B3), size: 20),
                const SizedBox(width: 10),
                Text(step.$1, style: TextStyle(fontWeight: done ? FontWeight.w800 : FontWeight.w500, color: done ? _text : _muted)),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 5),
          decoration: _card(),
          child: Column(children: [Icon(icon, color: _blue), const SizedBox(height: 6), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))]),
        ),
      );

  Widget _infoLine(IconData icon, String label, String value) => Row(
        children: [
          Icon(icon, color: _blue, size: 21),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(color: _muted))),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
        ],
      );

  Widget _primaryButton(String label, IconData icon, VoidCallback onPressed, {Color accent = _blue, Color foreground = Colors.white}) => SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: foreground, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ),
      );

  Widget _secondaryButton(String label, IconData icon, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
      );

  Widget _statusCard(String title, String subtitle, IconData icon) => Container(
        padding: const EdgeInsets.all(17),
        decoration: _card(),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(icon, color: _blue)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: _muted, height: 1.35))])),
          ],
        ),
      );

  BoxDecoration _card() => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE4E9F0)));

  void _sheet(String title, String body) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(color: _muted, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
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
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)]),
        child: Icon(icon, color: darkIcon ? _text : Colors.white, size: 22),
      );
}

class _RideMapPainter extends CustomPainter {
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
      final x = i * 82.0 + 24;
      canvas.drawLine(Offset(x, 0), Offset(x + 42, size.height), road);
    }
    final route = Paint()
      ..color = _blue
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(38, size.height - 40)
      ..cubicTo(size.width * .34, size.height * .7, size.width * .5, size.height * .55, size.width * .58, size.height * .47)
      ..cubicTo(size.width * .75, size.height * .33, size.width * .84, size.height * .26, size.width - 42, 45);
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

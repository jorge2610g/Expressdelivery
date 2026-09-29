import 'package:flutter/material.dart';

enum RidePreviewStage { idle, requested, accepted, arriving, inProgress, completed }

enum RidePreviewRole { customer, driver }

class RideFlowPreviewPage extends StatefulWidget {
  final VoidCallback onClose;

  const RideFlowPreviewPage({super.key, required this.onClose});

  @override
  State<RideFlowPreviewPage> createState() => _RideFlowPreviewPageState();
}

class _RideFlowPreviewPageState extends State<RideFlowPreviewPage> {
  RidePreviewRole role = RidePreviewRole.customer;
  RidePreviewStage stage = RidePreviewStage.idle;

  String get stageLabel => switch (stage) {
        RidePreviewStage.idle => 'Sin viaje activo',
        RidePreviewStage.requested => 'Buscando conductor',
        RidePreviewStage.accepted => 'Conductor asignado',
        RidePreviewStage.arriving => 'Conductor en camino',
        RidePreviewStage.inProgress => 'Viaje en curso',
        RidePreviewStage.completed => 'Viaje completado',
      };

  void requestRide() => setState(() => stage = RidePreviewStage.requested);
  void acceptRide() => setState(() => stage = RidePreviewStage.accepted);
  void markArriving() => setState(() => stage = RidePreviewStage.arriving);
  void startRide() => setState(() => stage = RidePreviewStage.inProgress);
  void completeRide() => setState(() => stage = RidePreviewStage.completed);
  void resetRide() => setState(() => stage = RidePreviewStage.idle);

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0B57D0);
    const bg = Color(0xFFF5F7FB);
    const text = Color(0xFF101828);
    const muted = Color(0xFF667085);

    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        scaffoldBackgroundColor: bg,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Preview Viajes conectado'),
          leading: IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final customer = _rolePanel(
                title: 'Cliente',
                icon: Icons.person_rounded,
                selected: role == RidePreviewRole.customer,
                onTap: () => setState(() => role = RidePreviewRole.customer),
              );
              final driver = _rolePanel(
                title: 'Conductor',
                icon: Icons.local_taxi_rounded,
                selected: role == RidePreviewRole.driver,
                onTap: () => setState(() => role = RidePreviewRole.driver),
              );

              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF073B8C), blue],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EXPRESS · VIAJES',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 1.1,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Un mismo viaje visto desde cliente y conductor',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Cambia de rol y avanza el estado para comprobar cómo se sincroniza visualmente el servicio.',
                          style: TextStyle(color: Color(0xFFDCEAFF), height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  wide
                      ? Row(children: [Expanded(child: customer), const SizedBox(width: 12), Expanded(child: driver)])
                      : Column(children: [customer, const SizedBox(height: 10), driver]),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: _card(),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF2FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.sync_rounded, color: blue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Estado compartido', style: TextStyle(color: muted, fontSize: 12)),
                              const SizedBox(height: 3),
                              Text(stageLabel, style: const TextStyle(color: text, fontSize: 19, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: 245,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFDCE3EC)),
                    ),
                    child: CustomPaint(
                      painter: _RideMapPainter(),
                      child: Stack(
                        children: [
                          const Positioned(
                            left: 26,
                            bottom: 28,
                            child: _MapDot(color: Color(0xFF12B76A), icon: Icons.person_rounded),
                          ),
                          const Positioned(
                            right: 30,
                            top: 26,
                            child: _MapDot(color: Color(0xFFF04438), icon: Icons.location_on_rounded),
                          ),
                          if (stage.index >= RidePreviewStage.accepted.index && stage != RidePreviewStage.completed)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: stage == RidePreviewStage.inProgress ? 88 : 126,
                              child: const Center(
                                child: _MapDot(color: Color(0xFFFFC928), icon: Icons.local_taxi_rounded, darkIcon: true),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  role == RidePreviewRole.customer
                      ? _customerControls()
                      : _driverControls(),
                  const SizedBox(height: 16),
                  _timeline(),
                  const SizedBox(height: 18),
                  const Center(
                    child: Text(
                      'Express v1.1.3 · build 11 · preview Viajes',
                      style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _rolePanel({required String title, required IconData icon, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? const Color(0xFF0B57D0) : const Color(0xFFE4E9F0), width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF0B57D0)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
            if (selected) const Icon(Icons.check_circle_rounded, color: Color(0xFF0B57D0)),
          ],
        ),
      ),
    );
  }

  Widget _customerControls() {
    switch (stage) {
      case RidePreviewStage.idle:
        return _actionCard(
          title: 'Solicitar un viaje',
          subtitle: 'Centro → Paitití · Express · Bs 5',
          button: 'Solicitar viaje',
          icon: Icons.local_taxi_rounded,
          onPressed: requestRide,
        );
      case RidePreviewStage.requested:
        return _statusCard('Buscando conductor cercano', 'Cambia a Conductor para aceptar esta misma solicitud.', Icons.radar_rounded);
      case RidePreviewStage.accepted:
        return _statusCard('Carlos aceptó tu viaje', 'Toyota Corolla · 123ABC · ★ 4.9', Icons.person_pin_circle_rounded);
      case RidePreviewStage.arriving:
        return _statusCard('Tu conductor va en camino', 'Llegada estimada: 3 min', Icons.directions_car_rounded);
      case RidePreviewStage.inProgress:
        return _statusCard('Viaje en curso', 'Destino: Av. Paitití · 12 min restantes', Icons.route_rounded);
      case RidePreviewStage.completed:
        return _actionCard(
          title: 'Viaje completado',
          subtitle: 'Total Bs 5 · Listo para calificar',
          button: 'Crear otro viaje',
          icon: Icons.check_circle_rounded,
          onPressed: resetRide,
        );
    }
  }

  Widget _driverControls() {
    switch (stage) {
      case RidePreviewStage.idle:
        return _statusCard('Sin solicitudes activas', 'Vuelve a Cliente y crea un viaje para verlo aparecer aquí.', Icons.inbox_outlined);
      case RidePreviewStage.requested:
        return _actionCard(
          title: 'Nueva solicitud',
          subtitle: 'Centro → Paitití · 3 min de recogida · Bs 5',
          button: 'Aceptar viaje',
          icon: Icons.notifications_active_rounded,
          onPressed: acceptRide,
        );
      case RidePreviewStage.accepted:
        return _actionCard(
          title: 'Viaje aceptado',
          subtitle: 'Juan Pérez · Centro → Paitití',
          button: 'Voy al pasajero',
          icon: Icons.navigation_rounded,
          onPressed: markArriving,
        );
      case RidePreviewStage.arriving:
        return _actionCard(
          title: 'Llegaste al punto de recogida',
          subtitle: 'Juan Pérez está esperando',
          button: 'Pasajero a bordo',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: startRide,
        );
      case RidePreviewStage.inProgress:
        return _actionCard(
          title: 'Viaje en curso',
          subtitle: 'Sigue la ruta hasta Av. Paitití',
          button: 'Completar viaje',
          icon: Icons.flag_rounded,
          onPressed: completeRide,
        );
      case RidePreviewStage.completed:
        return _statusCard('Servicio completado', 'El mismo estado ya aparece completado para el cliente.', Icons.check_circle_rounded);
    }
  }

  Widget _actionCard({required String title, required String subtitle, required String button, required IconData icon, required VoidCallback onPressed}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: const Color(0xFF0B57D0)), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Color(0xFF667085), height: 1.4)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(onPressed: onPressed, child: Text(button, style: const TextStyle(fontWeight: FontWeight.w800))),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: const Color(0xFFEAF2FF), child: Icon(icon, color: const Color(0xFF0B57D0))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: Color(0xFF667085), height: 1.35))])),
        ],
      ),
    );
  }

  Widget _timeline() {
    final steps = const [
      ('Solicitud', RidePreviewStage.requested),
      ('Aceptado', RidePreviewStage.accepted),
      ('En recogida', RidePreviewStage.arriving),
      ('En viaje', RidePreviewStage.inProgress),
      ('Completado', RidePreviewStage.completed),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Flujo del servicio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...steps.map((step) {
            final done = stage.index >= step.$2.index;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? const Color(0xFF0B57D0) : const Color(0xFF98A2B3), size: 20),
                const SizedBox(width: 10),
                Text(step.$1, style: TextStyle(fontWeight: done ? FontWeight.w800 : FontWeight.w500, color: done ? const Color(0xFF101828) : const Color(0xFF667085))),
              ]),
            );
          }),
        ],
      ),
    );
  }

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
        child: Icon(icon, color: darkIcon ? const Color(0xFF101828) : Colors.white, size: 22),
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
      final x = i * 82.0 + 22;
      canvas.drawLine(Offset(x, 0), Offset(x + 44, size.height), road);
    }
    final route = Paint()
      ..color = const Color(0xFF0B57D0)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(38, size.height - 42)
      ..cubicTo(size.width * .35, size.height * .72, size.width * .50, size.height * .55, size.width * .58, size.height * .46)
      ..cubicTo(size.width * .76, size.height * .32, size.width * .84, size.height * .25, size.width - 42, 44);
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

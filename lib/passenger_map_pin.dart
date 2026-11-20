import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Elegir el destino moviendo el mapa del inicio (solo cuentas de Prueba).
///
/// El marcador queda fijo al centro; al soltar y quedarse quieto el mapa, ese
/// punto pasa a ser el destino y se abre la confirmación de ruta.

/// Espera a que el mapa se quede quieto antes de fijar el destino.
const Duration kPinSettleDelay = Duration(milliseconds: 700);

/// Movimiento mínimo (metros) desde donde empezó el gesto para considerarlo
/// una elección y no un roce o un zoom con los dedos.
const double kPinCommitMinMeters = 40;

/// Distancia mínima (metros) entre el origen y el destino.
const double kPinTooCloseMeters = 25;

/// ¿El mapa se movió lo bastante desde el inicio del gesto?
bool pinMovedEnough(
  LatLng? start,
  LatLng end, {
  double minMeters = kPinCommitMinMeters,
}) {
  if (start == null) return false;
  return const Distance().as(LengthUnit.Meter, start, end) >= minMeters;
}

/// ¿El punto está demasiado cerca del origen? Misma regla que el selector.
bool pinTooCloseToPickup(
  LatLng pin, {
  required double? pickupLatitude,
  required double? pickupLongitude,
}) {
  if (pickupLatitude == null || pickupLongitude == null) return false;
  final meters = const Distance().as(
    LengthUnit.Meter,
    LatLng(pickupLatitude, pickupLongitude),
    pin,
  );
  return meters < kPinTooCloseMeters;
}

/// Marcador fijo al centro del mapa. La punta queda exactamente en el centro;
/// al mover el mapa se levanta y su sombra se achica. Cuando [nudge] cambia
/// (el usuario tocó «¿A dónde vas?») da un salto para indicar que se elige
/// moviendo el mapa.
class PassengerMapPin extends StatefulWidget {
  final bool moving;
  final int nudge;

  const PassengerMapPin({super.key, required this.moving, this.nudge = 0});

  @override
  State<PassengerMapPin> createState() => _PassengerMapPinState();
}

class _PassengerMapPinState extends State<PassengerMapPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didUpdateWidget(PassengerMapPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nudge != widget.nudge) _bounce.forward(from: 0);
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounce,
      builder: (context, _) {
        // Dos saltos suaves que se apagan.
        final t = _bounce.value;
        final jump = t == 0 || t == 1
            ? 0.0
            : (1 - t) * 16 * (0.5 - 0.5 * math.cos(t * math.pi * 4)).abs();
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: widget.moving ? 1 : 0),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          builder: (context, lift, _) {
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 16 - 6 * lift,
                  height: 6 - 2 * lift,
                  decoration: BoxDecoration(
                    color: const Color(0x40000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -26 - 12 * lift - jump),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 52,
                    color: Color(0xFF0B57D0),
                    shadows: [
                      Shadow(color: Color(0x55000000), blurRadius: 6),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Aviso corto arriba del mapa: invita a mover el mapa y avisa al soltar.
class PassengerMapHint extends StatelessWidget {
  final bool moving;
  final bool dark;

  const PassengerMapHint({super.key, required this.moving, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E0E1525),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: moving
                  ? const Color(0xFFFFB020)
                  : const Color(0xFF0B57D0),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              moving ? 'Suelta para fijar el destino' : 'Mueve el mapa para elegir',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dark ? Colors.white : const Color(0xFF0E1525),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

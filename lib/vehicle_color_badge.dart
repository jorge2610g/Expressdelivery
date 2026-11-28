import 'package:flutter/material.dart';

/// Color de un vehículo a partir del texto que escribió el conductor
/// («rojo», «Negro con rojo», «ploma»…). Devuelve null si no se reconoce.
Color? expressVehicleColorFromText(String? raw) {
  final text = (raw ?? '')
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
  if (text.trim().isEmpty) return null;
  const table = <String, Color>{
    'negr': Color(0xFF1D2025),
    'blanc': Color(0xFFFFFFFF),
    'roj': Color(0xFFD92D20),
    'vino': Color(0xFF7A1F2B),
    'guinda': Color(0xFF7A1F2B),
    'azul': Color(0xFF2E5BD8),
    'celest': Color(0xFF53B1FD),
    'verde': Color(0xFF12B76A),
    'amarill': Color(0xFFF5C451),
    'naranj': Color(0xFFF08A24),
    'anaranj': Color(0xFFF08A24),
    'plom': Color(0xFF8A94A6),
    'gris': Color(0xFF8A94A6),
    'plata': Color(0xFFB8C0CC),
    'plate': Color(0xFFB8C0CC),
    'dorad': Color(0xFFC9A227),
    'morad': Color(0xFF7A4DD8),
    'violet': Color(0xFF7A4DD8),
    'rosa': Color(0xFFF063A5),
    'marron': Color(0xFF7A4A2A),
    'cafe': Color(0xFF7A4A2A),
    'beige': Color(0xFFD9C7A3),
    'crema': Color(0xFFE8DCC0),
  };
  Color? best;
  var bestIndex = 1 << 30;
  table.forEach((key, color) {
    final i = text.indexOf(key);
    if (i >= 0 && i < bestIndex) {
      best = color;
      bestIndex = i;
    }
  });
  return best;
}

/// Moto (o auto) pintada del color que el conductor indicó en su vehículo.
class ExpressVehicleColorBadge extends StatelessWidget {
  const ExpressVehicleColorBadge({
    super.key,
    required this.vehicleType,
    required this.colorText,
    this.size = 44,
  });

  final String? vehicleType;
  final String? colorText;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = expressVehicleColorFromText(colorText) ?? const Color(0xFF98A2B3);
    final light = color.computeLuminance() > .6;
    final isCar = vehicleType == 'car' || vehicleType == 'xl';
    return Container(
      width: size + 8,
      height: size,
      decoration: BoxDecoration(
        color: light ? const Color(0xFF2B3340) : const Color(0xFFE8ECF3),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Icon(
        isCar ? Icons.directions_car_filled_rounded : Icons.two_wheeler_rounded,
        color: color,
        size: size * .72,
      ),
    );
  }
}

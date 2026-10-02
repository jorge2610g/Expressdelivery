import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

Future<bool> confirmExpressLocationUse(
  BuildContext context, {
  required bool continuousDriverTracking,
}) async {
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.denied) {
    return true;
  }
  if (!context.mounted) return false;

  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.location_on_outlined),
      title: Text(
        continuousDriverTracking
            ? 'Ubicación mientras estás en línea'
            : 'Ubicación para tu viaje',
      ),
      content: Text(
        continuousDriverTracking
            ? 'Express necesita tu ubicación precisa para mostrar tu posición '
                'a pasajeros cercanos y actualizar el viaje mientras estás '
                'En línea o en un servicio activo. Android mostrará una '
                'notificación persistente mientras el seguimiento esté activo. '
                'Puedes detenerlo pasando a Fuera de línea. Express no usa tu '
                'ubicación para publicidad.'
            : 'Express necesita tu ubicación para ubicar el punto de recogida, '
                'mostrar el mapa y calcular el servicio que solicitas. '
                'La ubicación se usa para funciones de transporte y seguridad, '
                'no para publicidad.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Ahora no'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Continuar'),
        ),
      ],
    ),
  );

  return accepted == true;
}

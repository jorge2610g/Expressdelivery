import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Checks the location grant needed to start Express's foreground location
/// service while the driver is visible in the app. Android continues that
/// service with an ongoing notification after the app is backgrounded.
Future<bool> ensureDriverBackgroundLocation(BuildContext context) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return true;
  }

  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse) {
    return true;
  }
  if (!context.mounted) return false;

  final openSettings = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.location_searching_rounded),
      title: const Text('Permite la ubicación'),
      content: const Text(
        'Para ponerte En línea, permite que Express use tu ubicación mientras usas la app. '
        'Mientras estés en línea, Express mantendrá un servicio visible con una notificación '
        'para actualizar tu ubicación aunque cambies a otra app. Si eliges Ahora no, '
        'seguirás desconectado.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Ahora no'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Permitir ubicación'),
        ),
      ],
    ),
  );

  if (openSettings != true) return false;
  if (permission == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings();
    return false;
  }
  final requested = await Geolocator.requestPermission();
  return requested == LocationPermission.whileInUse ||
      requested == LocationPermission.always;
}

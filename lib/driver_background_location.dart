import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Checks Android's actual background-location grant before allowing a driver
/// to go online. The OS setting is authoritative; Supabase cannot inspect a
/// permission stored on the device.
Future<bool> ensureDriverBackgroundLocation(BuildContext context) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return true;
  }

  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.always) return true;
  if (!context.mounted) return false;

  final openSettings = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.location_searching_rounded),
      title: const Text('Activa la ubicación en segundo plano'),
      content: const Text(
        'Para ponerte En línea y recibir solicitudes cuando Express esté en segundo plano, '
        'permite la ubicación todo el tiempo. En Android, abre los permisos de ubicación '
        'de Express y selecciona “Permitir todo el tiempo”. Al volver, pulsa En línea otra vez. '
        'Si eliges Ahora no, seguirás desconectado.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Ahora no'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Abrir ajustes'),
        ),
      ],
    ),
  );

  if (openSettings != true) return false;
  await Geolocator.openAppSettings();
  return false;
}

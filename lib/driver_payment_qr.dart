import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/express_service.dart';

const String driverPaymentQrBucket = 'driver-payment-qr';
const int driverPaymentQrMaxBytes = 5 * 1024 * 1024;

final RegExp _ownQrPathPattern =
    RegExp(r'^[0-9a-f-]{36}/qr/[0-9]+\.(png|jpe?g|webp)$');

const Map<String, String> _qrContentTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
};

/// Extensión normalizada (png, jpg o webp) o null si el archivo no es una
/// imagen permitida para el QR.
String? driverPaymentQrExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = fileName.substring(dot + 1).toLowerCase();
  if (!_qrContentTypes.containsKey(ext)) return null;
  return ext == 'jpeg' ? 'jpg' : ext;
}

String driverPaymentQrContentType(String ext) =>
    _qrContentTypes[ext] ?? 'image/jpeg';

/// Espejo de la regla del servidor: la ruta debe estar en la carpeta del
/// propio conductor. El servidor sigue siendo la autoridad.
bool isOwnDriverPaymentQrPath(String path, String userId) =>
    path.startsWith('$userId/') && _ownQrPathPattern.hasMatch(path);

/// El pasajero pide el QR solo cuando el conductor pidió el cobro con el viaje
/// en curso y el pago es con QR del conductor. Al completar el viaje se cierra.
bool passengerShouldLoadDriverQr(Map<String, dynamic> trip) =>
    trip['status']?.toString() == 'in_progress' &&
    trip['payment_requested_at'] != null &&
    isDriverQrPayment(trip);

/// Solo los pagos con QR del conductor muestran el QR. En efectivo u otro
/// método, el flujo no cambia.
bool isDriverQrPayment(Map<String, dynamic> trip) {
  final ride = trip['ride_requests'];
  if (ride is! Map) return false;
  return ride['payment_method']?.toString() == 'driver_qr';
}

/// Pre-paso de "Completar viaje" en pagos con QR. Si el conductor tiene QR
/// cargado, avisa al servidor del cobro antes de abrir la confirmación. Si
/// falla, avisa del error y devuelve false: no se abre el diálogo.
/// Sin QR cargado, el flujo es el de hoy.
Future<bool> requestQrChargeBeforeCompletion({
  required bool isDriverQr,
  required Future<String?> Function() qrPath,
  required Future<void> Function() request,
  required void Function(String message) onError,
}) async {
  if (!isDriverQr) return true;
  try {
    if (await qrPath() == null) return true;
    await request();
    return true;
  } catch (error) {
    final text = error is PostgrestException ? error.message : null;
    onError(text == null || text.isEmpty
        ? 'No se pudo avisar el cobro al pasajero. Inténtalo de nuevo.'
        : text);
    return false;
  }
}

typedef DriverQrUpload = Future<String> Function(
  Uint8List bytes,
  String ext,
  String contentType,
);

/// Orden de operaciones del QR. Reemplazar: subir el nuevo, registrarlo y
/// solo entonces borrar el anterior. Quitar: quitar la referencia primero.
class DriverPaymentQrActions {
  DriverPaymentQrActions({
    required this.userId,
    required this.upload,
    required this.setPath,
    required this.removeObject,
  });

  final String userId;
  final DriverQrUpload upload;
  final Future<void> Function(String? path) setPath;
  final Future<void> Function(String path) removeObject;

  Future<String> replace(
    Uint8List bytes,
    String ext, {
    String? currentPath,
  }) async {
    final newPath = await upload(bytes, ext, driverPaymentQrContentType(ext));
    if (!isOwnDriverPaymentQrPath(newPath, userId)) {
      throw StateError('Ruta de QR no válida.');
    }
    try {
      await setPath(newPath);
    } catch (_) {
      // Sin referencia registrada, el archivo nuevo queda huérfano: se borra.
      try {
        await removeObject(newPath);
      } catch (_) {}
      rethrow;
    }
    if (currentPath != null && currentPath != newPath) {
      try {
        await removeObject(currentPath);
      } catch (_) {
        // La referencia ya apunta al nuevo archivo; la limpieza es best-effort.
      }
    }
    return newPath;
  }

  Future<void> remove(String currentPath) async {
    await setPath(null);
    try {
      await removeObject(currentPath);
    } catch (_) {
      // Sin referencia, el archivo ya no se muestra; la limpieza es best-effort.
    }
  }
}

/// Lectura para el pasajero: pide la ruta a la RPC y descarga el archivo con
/// la política de lectura. Cualquier fallo devuelve null y la pantalla no cambia.
Future<Uint8List?> loadPassengerDriverPaymentQr(String tripId) async {
  try {
    final raw = await Supabase.instance.client.rpc(
      'passenger_trip_driver_payment_qr',
      params: {'p_trip_id': tripId},
    );
    final path = raw?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    return await Supabase.instance.client.storage
        .from(driverPaymentQrBucket)
        .download(path);
  } catch (_) {
    return null;
  }
}

/// Vista del QR del conductor. Solo presenta estado y avisa acciones.
class DriverPaymentQrView extends StatelessWidget {
  const DriverPaymentQrView({
    super.key,
    required this.imageBytes,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? imageBytes;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasQr = imageBytes != null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Muestra este QR al pasajero en el paso de cobro. Solo lo ve el '
          'pasajero de tu viaje y únicamente en ese paso.',
        ),
        const SizedBox(height: 16),
        Container(
          height: 260,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: hasQr
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(imageBytes!, fit: BoxFit.contain),
                )
              : const Text('Aún no cargaste tu QR de pago.'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : onPick,
          child: Text(hasQr ? 'Reemplazar QR' : 'Subir QR'),
        ),
        if (hasQr) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy ? null : onRemove,
            child: const Text('Quitar QR'),
          ),
        ],
      ],
    );
  }
}

/// Pantalla "Mi QR de pago" del perfil del conductor.
class DriverPaymentQrPage extends StatefulWidget {
  const DriverPaymentQrPage({super.key, required this.service});

  final ExpressService service;

  @override
  State<DriverPaymentQrPage> createState() => _DriverPaymentQrPageState();
}

class _DriverPaymentQrPageState extends State<DriverPaymentQrPage> {
  Uint8List? _bytes;
  String? _path;
  bool _loading = true;
  bool _busy = false;
  late final DriverPaymentQrActions _actions = DriverPaymentQrActions(
    userId: widget.service.userId,
    upload: (bytes, ext, contentType) =>
        widget.service.uploadDriverPaymentQr(bytes, ext, contentType),
    setPath: (path) async {
      await widget.service.setMyPaymentQrPath(path);
    },
    removeObject: widget.service.removeDriverPaymentQrObject,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final path = await widget.service.myPaymentQrPath();
      Uint8List? bytes;
      if (path != null) {
        bytes = await widget.service.downloadDriverPaymentQr(path);
      }
      if (!mounted) return;
      setState(() {
        _path = path;
        _bytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      _snack('No se pudo cargar tu QR de pago.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1600,
    );
    if (file == null) return;
    final ext = driverPaymentQrExtension(file.name);
    if (ext == null) {
      _snack('Usa una imagen PNG, JPG o WEBP.');
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > driverPaymentQrMaxBytes) {
      _snack('La imagen supera 5 MB.');
      return;
    }
    setState(() => _busy = true);
    try {
      final newPath = await _actions.replace(bytes, ext, currentPath: _path);
      if (!mounted) return;
      setState(() {
        _path = newPath;
        _bytes = bytes;
      });
    } catch (_) {
      if (mounted) _snack('No se pudo guardar el QR. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final current = _path;
    if (current == null) return;
    setState(() => _busy = true);
    try {
      await _actions.remove(current);
      if (!mounted) return;
      setState(() {
        _path = null;
        _bytes = null;
      });
    } catch (_) {
      if (mounted) _snack('No se pudo quitar el QR. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi QR de pago')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : DriverPaymentQrView(
              imageBytes: _bytes,
              busy: _busy,
              onPick: _pick,
              onRemove: _remove,
            ),
    );
  }
}


import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'call_overlay_sync.dart';
import 'driver_floating_offers.dart';
import 'driver_background_location.dart';
import 'services/express_service.dart';

/// Un servicio que el conductor puede tener activo o pendiente. La pantalla solo
/// informa: nada se activa al abrirla, y cada acción requiere un toque del usuario.
class _ServiceStatus {
  const _ServiceStatus({
    required this.title,
    required this.active,
    required this.activeText,
    required this.pendingText,
    required this.actionLabel,
    required this.onActivate,
    this.alwaysShowAction = false,
  });

  final String title;
  final bool active;
  final String activeText;
  final String pendingText;
  final String actionLabel;
  final Future<void> Function() onActivate;
  // Permite desactivar un servicio activo desde su propia fila.
  final bool alwaysShowAction;
}

/// Permisos y servicios del conductor: GPS, notificaciones, llamadas y ventana
/// flotante. Cada servicio muestra si está activo o pendiente, y el botón lleva a
/// los ajustes del servicio indicado.
class DriverPermissionsPage extends StatefulWidget {
  const DriverPermissionsPage({super.key, required this.service});

  final ExpressService service;

  @override
  State<DriverPermissionsPage> createState() => _DriverPermissionsPageState();
}

class _DriverPermissionsPageState extends State<DriverPermissionsPage>
    with WidgetsBindingObserver {
  List<_ServiceStatus>? items;
  // Solo se publica la lectura más reciente: una lectura anterior no pisa el estado nuevo.
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver de los ajustes del sistema se vuelve a leer cada permiso real.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final statuses = await _readStatuses();
    if (!mounted || seq != _loadSeq) return;
    setState(() => items = statuses);
  }

  Future<void> _activate(_ServiceStatus item) async {
    await item.onActivate();
    if (mounted) await _load();
  }

  Future<List<_ServiceStatus>> _readStatuses() async {
    final locationOn = await Geolocator.isLocationServiceEnabled();
    final locationPermission = await Geolocator.checkPermission();
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final gpsPermitted = locationPermission == LocationPermission.always ||
        locationPermission == LocationPermission.whileInUse;
    final notifications = await Permission.notification.status;
    final microphone = await Permission.microphone.status;
    final overlay = await isOverlayGranted();
    final bubbleOn =
        await DriverFloatingOfferSettings(accountId: widget.service.userId).isEnabled();

    return [
      _ServiceStatus(
        title: 'Ubicación (GPS)',
        active: locationOn && gpsPermitted,
        activeText: android
            ? 'Permiso activo. Al estar En línea, Express mantiene un servicio de ubicación visible con notificación.'
            : 'Activo. Express usa tu ubicación para ofrecerte viajes cercanos.',
        pendingText: !locationOn
            ? 'Pendiente. El GPS del teléfono está apagado. Se necesita activarlo para recibir viajes cercanos.'
            : 'Pendiente. Permite la ubicación de Express mientras usas la app para recibir viajes cercanos.',
        actionLabel: !locationOn
            ? 'Activar GPS'
            : 'Permitir ubicación',
        onActivate: () async {
          if (!locationOn) {
            await Geolocator.openLocationSettings();
          } else if (locationPermission == LocationPermission.denied) {
            await ensureDriverBackgroundLocation(context);
          } else if (locationPermission == LocationPermission.deniedForever) {
            await Geolocator.openAppSettings();
          } else {
            await Geolocator.requestPermission();
          }
        },
      ),
      _ServiceStatus(
        title: 'Notificaciones',
        active: notifications.isGranted,
        activeText: 'Activo. Te avisamos de las nuevas solicitudes.',
        pendingText: 'Pendiente. Sin notificaciones no verás los avisos de nuevas solicitudes.',
        actionLabel: 'Permitir notificaciones',
        onActivate: () async {
          final result = await Permission.notification.request();
          if (result.isPermanentlyDenied) await openAppSettings();
        },
      ),
      _ServiceStatus(
        title: 'Llamadas',
        active: microphone.isGranted,
        activeText: 'Activo. Tienes el micrófono para llamar y recibir llamadas dentro de la app.',
        pendingText: 'Pendiente. Se necesita el micrófono para llamar a tus clientes.',
        actionLabel: 'Permitir micrófono',
        onActivate: () async {
          final result = await Permission.microphone.request();
          if (result.isPermanentlyDenied) await openAppSettings();
        },
      ),
      _ServiceStatus(
        title: 'Ventana flotante',
        active: overlay && bubbleOn,
        activeText: 'Activo. Puede mostrar la burbuja sobre otras aplicaciones cuando Express está en segundo plano.',
        pendingText: overlay
            ? 'Permiso concedido. La burbuja está apagada: actívala si quieres verla.'
            : 'Pendiente. Puede mostrar la burbuja sobre otras aplicaciones cuando Express está en segundo plano. Es opcional y depende de los permisos del teléfono.',
        actionLabel: !overlay
            ? 'Acceso a la burbuja flotante'
            : bubbleOn
                ? 'Desactivar burbuja'
                : 'Activar burbuja',
        alwaysShowAction: true,
        onActivate: () async {
          // Abrir Ajustes de Android no registra nada: solo la elección del interruptor
          // (Activar/Desactivar) cambia la preferencia de Express.
          if (!overlay) {
            await openOverlayPermissionSettings();
          } else {
            await setBubbleEnabledByDriver(widget.service, !bubbleOn);
          }
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = items;
    return Scaffold(
      appBar: AppBar(title: const Text('Permisos y servicios')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Aquí ves qué servicios de Express están activos. Nada se activa solo: '
                  'tú decides cuándo cambiar cada uno.',
                ),
                const SizedBox(height: 16),
                for (final item in rows)
                  _ServiceCard(
                    item: item,
                    onActivate: () => _activate(item),
                  ),
              ],
            ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.item, required this.onActivate});

  final _ServiceStatus item;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = item.active ? Colors.green.shade700 : Colors.orange.shade800;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.active ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  item.active ? 'Activo' : 'Pendiente',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.active ? item.activeText : item.pendingText,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (!item.active || item.alwaysShowAction) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onActivate,
                  child: Text(item.actionLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'services/express_service.dart';

/// Carga la configuración pública (app_settings vía app_runtime_config).
typedef MaintenanceSettingsLoader = Future<Map<String, dynamic>> Function({
  bool forceRefresh,
});

const String kDefaultMaintenanceMessage =
    'Estamos realizando trabajos de mantenimiento. Vuelve a intentarlo en unos minutos.';

/// Solo el valor `true` del panel activa el mantenimiento.
bool maintenanceActiveFrom(Map<String, dynamic> settings) {
  final value = settings['maintenance_mode'];
  if (value is bool) return value;
  return value?.toString().trim().toLowerCase() == 'true';
}

String maintenanceMessageFrom(Map<String, dynamic> settings) {
  final value = settings['maintenance_message']?.toString().trim() ?? '';
  return value.isEmpty ? kDefaultMaintenanceMessage : value;
}

Future<Map<String, dynamic>> _defaultLoader({bool forceRefresh = false}) {
  return ExpressService().appSettings(forceRefresh: forceRefresh);
}

/// Muestra una pantalla de mantenimiento a pantalla completa cuando el
/// administrador enciende «Modo mantenimiento» en el panel.
///
/// - La app queda montada debajo, así no se pierde el estado al terminar.
/// - Si la consulta falla (sin conexión, error de red) no bloquea la app.
/// - Se vuelve a consultar cada [interval] y con el botón «Reintentar».
class MaintenanceGate extends StatefulWidget {
  final Widget child;
  final MaintenanceSettingsLoader? loader;
  final Duration interval;

  const MaintenanceGate({
    super.key,
    required this.child,
    this.loader,
    this.interval = const Duration(minutes: 2),
  });

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  Timer? _timer;
  bool _active = false;
  bool _checking = false;
  String _message = kDefaultMaintenanceMessage;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(widget.interval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final loader = widget.loader ?? _defaultLoader;
      final settings = await loader(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _active = maintenanceActiveFrom(settings);
        _message = maintenanceMessageFrom(settings);
      });
    } catch (_) {
      // Si no se puede consultar, la app sigue como estaba antes.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return widget.child;

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        // Absorbe los toques que caen fuera de la pantalla de mantenimiento.
        const Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Colors.transparent,
          ),
        ),
        Positioned.fill(
          child: Material(
            color: const Color(0xFFF5F7FB),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                          radius: 34,
                          backgroundColor: Color(0xFF0B57D0),
                          child: Icon(
                            Icons.construction_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Express está en mantenimiento',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF4B5563),
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _check,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

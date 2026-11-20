import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'core/runtime_channel.dart';
import 'services/express_service.dart';

/// Carga la configuración pública (app_settings vía app_runtime_config).
typedef MaintenanceSettingsLoader =
    Future<Map<String, dynamic>> Function({bool forceRefresh});

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
/// - Solo bloquea una sesión iniciada cuyo entorno ya se resolvió como
///   Producción. Sin sesión se ve el inicio de sesión, y en Preview nunca se
///   muestra ni se consulta el servidor.
/// - Al volver a iniciar sesión se reconoce el entorno de la cuenta: Preview
///   pasa, Producción queda bloqueada.
/// - La pantalla tiene un icono arriba para cerrar sesión.
/// - La app queda montada debajo, así no se pierde el estado al terminar.
/// - Si la consulta falla (sin conexión, error de red) no bloquea la app.
/// - Se vuelve a consultar cada [interval] y con el botón «Reintentar».
class MaintenanceGate extends StatefulWidget {
  final Widget child;
  final MaintenanceSettingsLoader? loader;
  final Duration interval;

  /// ¿La cuenta es de Preview? Si es así, no se bloquea.
  final ValueListenable<bool>? previewListenable;

  /// ¿Ya se resolvió el entorno de la cuenta? Es falso sin sesión iniciada.
  final ValueListenable<bool>? resolvedListenable;

  /// Cierra la sesión actual (el icono de arriba de la pantalla).
  final Future<void> Function()? onSignOut;

  const MaintenanceGate({
    super.key,
    required this.child,
    this.loader,
    this.interval = const Duration(minutes: 2),
    this.previewListenable,
    this.resolvedListenable,
    this.onSignOut,
  });

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  Timer? _timer;
  bool _active = false;
  bool _checking = false;
  bool _signingOut = false;
  String _message = kDefaultMaintenanceMessage;

  ValueListenable<bool> get _preview =>
      widget.previewListenable ?? ExpressRuntimeChannel.previewModeListenable;

  ValueListenable<bool> get _resolved =>
      widget.resolvedListenable ?? ExpressRuntimeChannel.resolvedListenable;

  // El mantenimiento solo aplica a una sesión de Producción ya reconocida.
  bool get _applies => _resolved.value && !_preview.value;

  @override
  void initState() {
    super.initState();
    _preview.addListener(_onEnvironmentChanged);
    _resolved.addListener(_onEnvironmentChanged);
    _check();
    _timer = Timer.periodic(widget.interval, (_) => _check());
  }

  @override
  void dispose() {
    _preview.removeListener(_onEnvironmentChanged);
    _resolved.removeListener(_onEnvironmentChanged);
    _timer?.cancel();
    super.dispose();
  }

  // Al iniciar o cerrar sesión cambia el entorno: en Producción se consulta
  // enseguida; en Preview o sin sesión la pantalla se oculta sola.
  void _onEnvironmentChanged() {
    if (_applies) _check();
  }

  Future<void> _check() async {
    // Preview y la pantalla de inicio de sesión nunca consultan el mantenimiento.
    if (!_applies) return;
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

  Future<void> _signOut() async {
    final action = widget.onSignOut;
    if (action == null || _signingOut) return;
    setState(() => _signingOut = true);
    try {
      await action();
    } catch (_) {
      // Si falla, la pantalla sigue y el usuario puede reintentar.
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_preview, _resolved]),
      builder: (context, _) {
        // La app siempre va en la misma posición del árbol: al encender o
        // apagar el mantenimiento no se reinicia la navegación.
        return Stack(
          children: [
            Positioned.fill(child: widget.child),
            if (_active && _applies) ..._overlay(),
          ],
        );
      },
    );
  }

  List<Widget> _overlay() {
    return [
      // Absorbe los toques que caen fuera de la pantalla de mantenimiento.
      const Positioned.fill(
        child: ModalBarrier(dismissible: false, color: Colors.transparent),
      ),
      Positioned.fill(
        child: Material(
          color: const Color(0xFFF5F7FB),
          child: SafeArea(
            child: Stack(
              children: [
                Center(
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
                if (widget.onSignOut != null)
                  Positioned(
                    top: 4,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Cerrar sesión',
                      onPressed: _signingOut ? null : _signOut,
                      icon: _signingOut
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.logout_rounded,
                              color: Color(0xFF374151),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

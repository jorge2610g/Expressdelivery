import 'package:flutter/material.dart';

import 'call_overlay_sync.dart';
import 'services/express_service.dart';

/// Llamadas de Express. Las llamadas se hacen por internet y dependen de la
/// sobreposición de pantalla, que se activa automáticamente al concederla.
/// El conductor ve además el estado de la sobreposición, que también controla
/// su burbuja de ofertas. El pasajero no tiene burbuja.
class CallPreferencesPage extends StatefulWidget {
  const CallPreferencesPage({
    super.key,
    required this.service,
    this.isDriver = false,
  });

  final ExpressService service;
  final bool isDriver;

  @override
  State<CallPreferencesPage> createState() => _CallPreferencesPageState();
}

class _CallPreferencesPageState extends State<CallPreferencesPage>
    with WidgetsBindingObserver {
  bool loading = true;
  bool overlayGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver de los ajustes del sistema se relee el permiso real.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshOverlay();
  }

  Future<void> _load() async {
    final granted = await isOverlayGranted();
    if (!mounted) return;
    setState(() {
      overlayGranted = granted;
      loading = false;
    });
    await syncOverlayCallPreference(widget.service);
  }

  Future<void> _refreshOverlay() async {
    final granted = await isOverlayGranted();
    if (!mounted || granted == overlayGranted) return;
    setState(() => overlayGranted = granted);
    await syncOverlayCallPreference(widget.service);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Llamadas')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.isDriver) ...[
                  Card(
                    child: ListTile(
                      leading: Icon(
                        overlayGranted
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        color: overlayGranted ? Colors.green : scheme.error,
                      ),
                      title: const Text('Sobreposición de pantalla'),
                      subtitle: Text(
                        overlayGranted
                            ? 'Activada'
                            : 'Desactivada. Actívala para ver las ofertas sobre otras apps.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: SwitchListTile(
                    title: const Text('Llamadas por internet'),
                    subtitle: const Text(
                      'Se activa automáticamente cuando la sobreposición de pantalla está activa.',
                    ),
                    value: overlayGranted,
                    onChanged: null,
                  ),
                ),
              ],
            ),
    );
  }
}

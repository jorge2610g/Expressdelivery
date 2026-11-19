import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_setup.dart';
import 'services/express_service.dart';

/// Aviso para conductores cuya foto de perfil se reemplazó por error. Solo se
/// muestra si la base marca al conductor (`my_driver_profile_photo_reupload_required`).
/// Abre directamente el paso de «Foto de perfil» del registro de conductor.
class DriverPhotoReuploadBanner extends StatefulWidget {
  const DriverPhotoReuploadBanner({super.key, required this.service});

  final ExpressService service;

  @override
  State<DriverPhotoReuploadBanner> createState() => _DriverPhotoReuploadBannerState();
}

class _DriverPhotoReuploadBannerState extends State<DriverPhotoReuploadBanner> {
  bool _required = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'my_driver_profile_photo_reupload_required',
      );
      if (mounted) setState(() => _required = raw == true);
    } catch (error, stack) {
      // Si no se puede leer, no se muestra el aviso y la cuenta sigue normal.
      debugPrint('Express driver photo reupload check failed: $error\n$stack');
    }
  }

  Future<void> _open() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverSetupPage(
          service: widget.service,
          editExisting: true,
          focusSection: 'profile',
        ),
      ),
    );
    if (mounted) await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (!_required) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_circle_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tu foto de perfil fue rechazada',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Vuelve a subir tu foto de perfil. El administrador la revisará antes de que puedas volver a ponerte en línea.',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _open,
                child: const Text('Subir foto'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

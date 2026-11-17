import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'passenger_verification.dart';

/// Pide al pasajero los pasos pendientes antes de pedir un viaje.
/// Devuelve true cuando ya no falta ninguno.
class PassengerVerificationPage extends StatefulWidget {
  const PassengerVerificationPage({
    super.key,
    required this.service,
    required this.initial,
  });

  final PassengerVerificationService service;
  final PassengerVerificationState initial;

  @override
  State<PassengerVerificationPage> createState() =>
      _PassengerVerificationPageState();
}

class _PassengerVerificationPageState extends State<PassengerVerificationPage> {
  late PassengerVerificationState _state = widget.initial;
  PassengerVerificationStep? _busyStep;
  String? _error;

  String get _userId => widget.service.client.auth.currentUser?.id ?? '';

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _capture(PassengerVerificationStep step) async {
    final source = step == PassengerVerificationStep.faceSelfie
        ? ImageSource.camera
        : await _chooseSource();
    if (source == null) return;

    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 86,
      maxWidth: 2200,
    );
    if (file == null) return;

    final extension = passengerImageExtension(file.name);
    if (extension == null) {
      setState(() => _error = 'Usa una foto en formato JPG, PNG o WebP.');
      return;
    }

    setState(() {
      _busyStep = step;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      if (step == PassengerVerificationStep.profilePhoto) {
        await widget.service.uploadProfilePhoto(
          userId: _userId,
          bytes: bytes,
          extension: extension,
        );
      } else {
        await widget.service.submitDocument(
          userId: _userId,
          step: step,
          bytes: bytes,
          extension: extension,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
      final next = await widget.service.fetchState();
      if (!mounted) return;
      setState(() => _state = next);
      if (next.isComplete) Navigator.pop(context, true);
    } catch (error, stack) {
      debugPrint('Express passenger verification upload failed: $error\n$stack');
      if (mounted) {
        setState(() => _error = 'No se pudo subir. Intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _busyStep = null);
    }
  }

  ({String title, String text, IconData icon}) _copy(PassengerVerificationStep step) {
    return switch (step) {
      PassengerVerificationStep.profilePhoto => (
          title: 'Foto de perfil',
          text: 'El conductor ve tu foto al solicitar tu viaje.',
          icon: Icons.account_circle_outlined,
        ),
      PassengerVerificationStep.identityFront => (
          title: 'Carnet de identidad, frente',
          text: 'Solo lo revisa el administrador de Express.',
          icon: Icons.badge_outlined,
        ),
      PassengerVerificationStep.identityBack => (
          title: 'Carnet de identidad, reverso',
          text: 'Solo lo revisa el administrador de Express.',
          icon: Icons.badge_outlined,
        ),
      PassengerVerificationStep.faceSelfie => (
          title: 'Selfie para reconocimiento facial',
          text: 'Mira a la cámara, con buena luz y sin lentes oscuros.',
          icon: Icons.face_retouching_natural_outlined,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pending = _state.pendingSteps;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Para tu seguridad y la de los conductores, completa estos datos antes de pedir un viaje.',
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          for (final step in pending)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(_copy(step).icon, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _copy(step).title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(_copy(step).text),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _busyStep == step
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : FilledButton(
                            onPressed: _busyStep != null ? null : () => _capture(step),
                            child: Text(
                              step == PassengerVerificationStep.faceSelfie
                                  ? 'Tomar selfie'
                                  : 'Subir',
                            ),
                          ),
                  ],
                ),
              ),
            ),
          if (pending.isEmpty)
            const Text('Ya tienes todo listo.'),
        ],
      ),
    );
  }
}

/// Abre la verificación si falta algún paso. Devuelve true si el pasajero puede
/// seguir. Si el estado no se puede leer, no bloquea: el servidor aún no exige
/// estos datos al crear el viaje.
Future<bool> ensurePassengerVerified(BuildContext context) async {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) return true;

  final service = PassengerVerificationService(client);
  final PassengerVerificationState state;
  try {
    state = await service.fetchState();
  } catch (error, stack) {
    debugPrint('Express passenger verification check failed: $error\n$stack');
    return true;
  }
  if (state.isComplete) return true;
  if (!context.mounted) return false;

  final done = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => PassengerVerificationPage(service: service, initial: state),
    ),
  );
  return done == true;
}

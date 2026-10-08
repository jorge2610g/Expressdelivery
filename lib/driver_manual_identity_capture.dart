import 'package:flutter/material.dart';

/// Guided manual identity intake. Captures are NOT automatically verified.
/// The caller uploads directly to the existing private driver-onboarding bucket.
class DriverManualIdentityCaptureResult {
  const DriverManualIdentityCaptureResult({
    required this.documentNumber,
    required this.frontPath,
    required this.backPath,
    required this.selfiePath,
  });
  final String documentNumber;
  final String frontPath;
  final String backPath;
  final String selfiePath;
}

class DriverManualIdentityCapturePage extends StatefulWidget {
  const DriverManualIdentityCapturePage({
    super.key,
    required this.uploadCameraPhoto,
    this.initialDocumentNumber = '',
    this.initialFrontPath,
    this.initialBackPath,
    this.initialSelfiePath,
  });

  final Future<String?> Function(String slot) uploadCameraPhoto;
  final String initialDocumentNumber;
  final String? initialFrontPath;
  final String? initialBackPath;
  final String? initialSelfiePath;

  @override
  State<DriverManualIdentityCapturePage> createState() =>
      _DriverManualIdentityCapturePageState();
}

class _DriverManualIdentityCapturePageState
    extends State<DriverManualIdentityCapturePage> {
  final _number = TextEditingController();
  int _step = 0;
  bool _busy = false;
  String? _front, _back, _selfie;

  @override
  void initState() {
    super.initState();
    _number.text = widget.initialDocumentNumber;
    _front = widget.initialFrontPath;
    _back = widget.initialBackPath;
    _selfie = widget.initialSelfiePath;
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _capture(String slot) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await widget.uploadCameraPhoto(slot);
      if (!mounted || path == null || path.isEmpty) return;
      setState(() {
        if (slot == 'front') _front = path;
        if (slot == 'back') _back = path;
        if (slot == 'selfie') _selfie = path;
        if (_step < 3) _step++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu documento ha sido cargado exitosamente.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No pudimos guardar la imagen. Vuelve a intentarlo.'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _captureInstructions({
    required String title,
    required String hint,
    required String slot,
    required IconData icon,
    required String? savedPath,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 70, color: scheme.primary),
        const SizedBox(height: 15),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(hint, textAlign: TextAlign.center),
        const SizedBox(height: 25),
        Container(
          width: 290,
          height: 175,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.primary, width: 2),
            borderRadius: BorderRadius.circular(22),
            color: scheme.primaryContainer.withValues(alpha: .25),
          ),
          child: savedPath?.isNotEmpty == true
              ? const Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 45,
                        color: Color(0xFF067647)),
                    SizedBox(height: 9),
                    Text('Documento cargado'),
                  ])
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.center_focus_strong_rounded, size: 44),
                  const SizedBox(height: 10),
                  Text(slot == 'selfie'
                      ? 'Coloca tu rostro en el centro'
                      : 'Coloca el documento dentro del marco'),
                ]),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : () => _capture(slot),
          icon: Icon(slot == 'selfie'
              ? Icons.face_rounded : Icons.photo_camera_outlined),
          label: Text(_busy ? 'Guardando…'
              : savedPath?.isNotEmpty == true
                  ? 'Repetir fotografía' : 'Abrir cámara'),
        ),
        if (savedPath?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: _busy ? null : () =>
              setState(() => _step = (_step + 1).clamp(0, 3)),
              child: const Text('Continuar')),
        ],
      ],
    );
  }

  Widget _page() {
    switch (_step) {
      case 0:
        return _captureInstructions(
          title: 'Carga el frente de tu carné',
          hint: 'Toma una foto clara del frente.',
          slot: 'front', icon: Icons.badge_outlined, savedPath: _front);
      case 1:
        return _captureInstructions(
          title: 'Carga el reverso de tu carné',
          hint: 'Toma una foto clara del reverso.',
          slot: 'back', icon: Icons.flip_rounded, savedPath: _back);
      case 2:
        return _captureInstructions(
          title: 'Carga tu fotografía facial',
          hint: 'Mira a la cámara y toma tu fotografía.',
          slot: 'selfie', icon: Icons.face_retouching_natural_rounded,
          savedPath: _selfie);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.fact_check_outlined, size: 63,
              color: Color(0xFF067647)),
          const SizedBox(height: 12),
          const Text('Revisa tus documentos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 15),
          const Text('País del documento: Bolivia'),
          const Text('Tipo: Carné de identidad'),
          const SizedBox(height: 16),
          TextField(
            controller: _number,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Número de documento *',
              hintText: 'Escribe el número que aparece en tu carné',
            ),
          ),
          const SizedBox(height: 12),
          const Text('✓ Frente recibido\n✓ Reverso recibido\n'
              '✓ Fotografía facial recibida'),
          const SizedBox(height: 12),
          const Text('Un administrador revisará tu información. '
              'La revisión puede tardar 24 horas o más.'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () {
              if (_number.text.trim().isEmpty ||
                  _front == null || _back == null || _selfie == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Completa el número y las tres imágenes.'),
                ));
                return;
              }
              Navigator.pop(context, DriverManualIdentityCaptureResult(
                documentNumber: _number.text.trim(),
                frontPath: _front!,
                backPath: _back!,
                selfiePath: _selfie!,
              ));
            },
            child: const Text('Guardar documentos para revisión'),
          ),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación Express · Bolivia')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          LinearProgressIndicator(value: (_step + 1) / 4),
          const SizedBox(height: 13),
          Text('Paso ${_step + 1} de 4 · Verificación manual',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 22),
          _page(),
          if (_step > 0) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _busy ? null : () => setState(() => _step--),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Volver al paso anterior'),
            ),
          ],
        ],
      )),
    );
  }
}

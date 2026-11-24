import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'core/supabase_client.dart';
import 'design/express_tokens.dart';

/// Imagen que se elige de la galería (o del computador) y se sube sola al depósito público
/// de imágenes de restaurantes; deja la dirección en [controller].
class RestaurantImageUploadField extends StatefulWidget {
  const RestaurantImageUploadField({
    required this.controller,
    required this.label,
    required this.enabled,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  State<RestaurantImageUploadField> createState() => _RestaurantImageUploadFieldState();
}

class _RestaurantImageUploadFieldState extends State<RestaurantImageUploadField> {
  bool _uploading = false;
  String? _error;

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final image = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1600, imageQuality: 86);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        setState(() => _error = 'La imagen debe pesar menos de 5 MB.');
        return;
      }
      setState(() => _uploading = true);
      final name = image.name.toLowerCase();
      final ext = name.endsWith('.png') ? 'png' : name.endsWith('.webp') ? 'webp' : 'jpg';
      final mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) throw StateError('Sesión no válida');
      final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await supabase.storage.from('marketplace-merchant-applications').uploadBinary(
          path, bytes, fileOptions: FileOptions(contentType: mime));
      final url = supabase.storage
          .from('marketplace-merchant-applications')
          .getPublicUrl(path);
      if (mounted) setState(() => widget.controller.text = url);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo subir la imagen. Intenta con otra.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 84,
            height: 84,
            color: ExpressColors.raised,
            child: url.isEmpty
                ? const Icon(Icons.image_outlined, color: ExpressColors.textFaint, size: 32)
                : Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
          ),
        ),
        const SizedBox(width: 14),
        if (widget.enabled)
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton.tonalIcon(
                onPressed: _uploading ? null : _pick,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_library_outlined),
                label: Text(url.isEmpty ? 'Elegir de la galería' : 'Cambiar imagen'),
              ),
              if (url.isNotEmpty)
                TextButton(
                    onPressed: _uploading
                        ? null
                        : () => setState(() => widget.controller.text = ''),
                    child: const Text('Quitar')),
            ]),
          ),
      ]),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_error!, style: const TextStyle(color: ExpressColors.coral)),
        ),
    ]);
  }
}

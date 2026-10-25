import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';

class RestaurantApplicationPage extends StatefulWidget {
  const RestaurantApplicationPage({super.key, this.previous});

  final Map<String, dynamic>? previous;

  @override
  State<RestaurantApplicationPage> createState() =>
      _RestaurantApplicationPageState();
}

class _RestaurantApplicationPageState extends State<RestaurantApplicationPage> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _map = MapController();
  final _picker = ImagePicker();
  LatLng _point = const LatLng(-20.214, -70.153);
  Uint8List? _logoBytes;
  Uint8List? _coverBytes;
  String _logoMime = 'image/jpeg';
  String _coverMime = 'image/jpeg';
  String? _logoUrl;
  String? _coverUrl;
  bool _busy = false;
  String? _message;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    final row = widget.previous;
    _name.text = row?['restaurant_name']?.toString() ?? '';
    _address.text = row?['address']?.toString() ?? '';
    _logoUrl = row?['logo_url']?.toString();
    _coverUrl = row?['cover_image_url']?.toString();
    final lat = double.tryParse(row?['latitude']?.toString() ?? '');
    final lng = double.tryParse(row?['longitude']?.toString() ?? '');
    if (lat != null && lng != null) _point = LatLng(lat, lng);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool logo}) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final filename = picked.name.toLowerCase();
    final mime = picked.mimeType ??
        (filename.endsWith('.png')
            ? 'image/png'
            : filename.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg');
    if (!const {'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
      _show('Usa una imagen JPG, PNG o WebP.');
      return;
    }
    if (bytes.length > 8 * 1024 * 1024) {
      _show('La imagen debe pesar menos de 8 MB.');
      return;
    }
    setState(() {
      if (logo) {
        _logoBytes = bytes;
        _logoMime = mime;
      } else {
        _coverBytes = bytes;
        _coverMime = mime;
      }
    });
  }

  Future<String> _upload(
    Uint8List bytes,
    String kind,
    String contentType,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw StateError('Inicia sesión para subir imágenes.');
    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path =
        '${user.id}/${DateTime.now().microsecondsSinceEpoch}-$kind.$extension';
    await supabase.storage
        .from('marketplace-merchant-applications')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return supabase.storage
        .from('marketplace-merchant-applications')
        .getPublicUrl(path);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final user = supabase.auth.currentUser;
    if (user == null || user.email == null) {
      _show('Inicia sesión con correo y contraseña o con Google.');
      return;
    }
    if (_name.text.trim().length < 2 || _address.text.trim().length < 4) {
      _show('Escribe el nombre y la dirección del restaurante.');
      return;
    }
    if (_logoBytes == null && (_logoUrl?.isEmpty ?? true)) {
      _show('Selecciona el logo del restaurante.');
      return;
    }
    if (_coverBytes == null && (_coverUrl?.isEmpty ?? true)) {
      _show('Selecciona una foto de portada.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_logoBytes != null) {
        _logoUrl = await _upload(_logoBytes!, 'logo', _logoMime);
      }
      if (_coverBytes != null) {
        _coverUrl = await _upload(_coverBytes!, 'cover', _coverMime);
      }
      await supabase.rpc(
        'marketplace_submit_merchant_application',
        params: {
          'p_channel': ExpressRuntimeChannel.name,
          'p_email': user.email,
          'p_restaurant_name': _name.text.trim(),
          'p_logo_url': _logoUrl,
          'p_cover_image_url': _coverUrl,
          'p_address': _address.text.trim(),
          'p_latitude': _point.latitude,
          'p_longitude': _point.longitude,
        },
      );
      if (mounted) {
        setState(() {
          _success = true;
          _message = 'Solicitud enviada. Express revisará los datos del local.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'No se pudo enviar la solicitud. Revisa las imágenes y vuelve a intentar.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _imageButton({required bool logo}) {
    final bytes = logo ? _logoBytes : _coverBytes;
    final url = logo ? _logoUrl : _coverUrl;
    final title = logo ? 'Logo del restaurante' : 'Foto de portada';
    return OutlinedButton.icon(
      onPressed: _busy ? null : () => _pickImage(logo: logo),
      icon: Icon(logo ? Icons.storefront_outlined : Icons.image_outlined),
      label: Text(
        bytes != null || (url?.isNotEmpty ?? false)
            ? '$title · lista'
            : 'Subir $title',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    if (_success) {
      return _statusCard(
        icon: Icons.hourglass_top_rounded,
        title: 'Solicitud enviada',
        text: _message ?? 'Tu restaurante está pendiente de revisión.',
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar restaurante')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Datos del restaurante',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'Completa la solicitud. El restaurante aparecerá en Express después de la aprobación del administrador.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nombre del restaurante',
                  prefixIcon: Icon(Icons.storefront_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Correo de acceso',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(user?.email ?? ''),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [_imageButton(logo: true), _imageButton(logo: false)],
              ),
              if (_logoBytes != null || _coverBytes != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_logoBytes != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _logoBytes!,
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    if (_coverBytes != null)
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _coverBytes!,
                            height: 76,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Dirección escrita',
                  hintText: 'Calle, número y referencia',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Toca el mapa para marcar el punto exacto del local.'),
              const SizedBox(height: 8),
              SizedBox(
                height: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _point,
                      initialZoom: 13,
                      onTap: (tapPosition, point) =>
                          setState(() => _point = point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'online.expressviajes',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _point,
                            width: 48,
                            height: 48,
                            child: const Icon(
                              Icons.location_pin,
                              size: 46,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ubicación: ${_point.latitude.toStringAsFixed(5)}, '
                '${_point.longitude.toStringAsFixed(5)}',
              ),
              if (widget.previous?['review_note'] != null) ...[
                const SizedBox(height: 12),
                _statusCard(
                  icon: Icons.info_outline,
                  title: 'Revisa la observación de Express',
                  text: widget.previous!['review_note'].toString(),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_busy ? 'Enviando…' : 'Enviar a revisión'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required String title,
    required String text,
  }) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 44, color: const Color(0xFF2563EB)),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(text, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text(
                  'La aprobación habilitará el panel del restaurante.',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'business_hours.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'design/express_tokens.dart';
import 'money_format.dart';
import 'restaurant_web_tools.dart';
import 'services/express_service.dart';

Future<dynamic> _rpc(String fn, Map<String, dynamic> params) => supabase.rpc(
      fn,
      params: {...params, 'p_channel': ExpressRuntimeChannel.name},
    );

Map<String, dynamic> _asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _asList(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

String _err(Object e) => ExpressRuntimeChannel.userSafeError(e,
    fallback: 'No se pudo completar la acción. Intenta de nuevo.');

void _snack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));
}

/// Contenedor común de las secciones: ancho máximo y márgenes.
class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.children, this.maxWidth = 900});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children),
            ),
          ),
        ],
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = 18});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: ExpressColors.surface,
          border: Border.all(color: ExpressColors.border),
          borderRadius: BorderRadius.circular(ExpressRadii.card),
        ),
        child: child,
      );
}

Widget _title(String text, {String? sub}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: ExpressColors.text)),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(sub,
                style: const TextStyle(color: ExpressColors.textMuted)),
          ),
      ]),
    );

Widget _loadingOrError(
    {required bool loading, String? error, required VoidCallback retry}) {
  if (loading) return const Center(child: CircularProgressIndicator());
  return Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(error ?? 'No se pudo cargar.', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      FilledButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar')),
    ]),
  );
}

// ───────────────────────────── Perfil ─────────────────────────────

class RestaurantProfilePage extends StatefulWidget {
  const RestaurantProfilePage({super.key, required this.merchantId});
  final String merchantId;

  @override
  State<RestaurantProfilePage> createState() => _RestaurantProfilePageState();
}

class _RestaurantProfilePageState extends State<RestaurantProfilePage> {
  Map<String, dynamic>? _p;
  String? _error;
  bool _saving = false;
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _minimum = TextEditingController();
  final _etaMin = TextEditingController();
  final _etaMax = TextEditingController();
  final _image = TextEditingController();
  final _cover = TextEditingController();
  final _transfer = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _description, _address, _minimum, _etaMin, _etaMax, _image, _cover, _transfer
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canEdit {
    final role = _p?['role']?.toString();
    return role == 'owner' || role == 'manager';
  }

  Future<void> _load() async {
    setState(() {
      _p = null;
      _error = null;
    });
    try {
      final p = _asMap(await _rpc(
          'marketplace_merchant_profile', {'p_merchant_id': widget.merchantId}));
      if (!mounted) return;
      String t(String k) => p[k]?.toString() ?? '';
      _description.text = t('description');
      _address.text = t('address');
      _minimum.text = p['minimum_order'] == null
          ? ''
          : (double.tryParse(t('minimum_order')) ?? 0).toStringAsFixed(0);
      _etaMin.text = t('eta_min_minutes');
      _etaMax.text = t('eta_max_minutes');
      _image.text = t('image_url');
      _cover.text = t('cover_image_url');
      _transfer.text = t('transfer_instructions');
      setState(() => _p = p);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _rpc('marketplace_merchant_update_profile', {
        'p_merchant_id': widget.merchantId,
        'p_description': _description.text,
        'p_image_url': _image.text,
        'p_cover_image_url': _cover.text,
        'p_address': _address.text,
        'p_minimum_order': double.tryParse(_minimum.text.trim()),
        'p_eta_min': int.tryParse(_etaMin.text.trim()),
        'p_eta_max': int.tryParse(_etaMax.text.trim()),
        'p_transfer_instructions': _transfer.text,
      });
      _snack(context, 'Perfil guardado.');
    } catch (e) {
      _snack(context, _err(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c,
          {int lines = 1, TextInputType? type, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          enabled: _canEdit,
          maxLines: lines,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 150,
              child: Text(label,
                  style: const TextStyle(color: ExpressColors.textMuted))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return _loadingOrError(
          loading: _error == null, error: _error, retry: _load);
    }
    final currency = p['currency']?.toString() ?? 'BOB';
    final hours = formatBusinessHours(p['business_hours']);
    return _PageFrame(maxWidth: 760, children: [
      _title('Perfil del restaurante',
          sub: _canEdit
              ? 'Lo que escribas aquí lo ven tus clientes.'
              : 'Solo el dueño o el encargado pueden editar el perfil.'),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _info('Nombre', p['name']?.toString() ?? '—'),
          _info('Categoría', p['category_key']?.toString() ?? '—'),
          _info('Costo de envío',
              p['delivery_fee'] == null ? '—' : expressMoney(p['delivery_fee'], currency)),
          _info(
              'Calificación',
              (p['review_count'] ?? 0) == 0
                  ? (p['rating'] == null ? 'Sin reseñas' : '${p['rating']}')
                  : '${p['rating']} (${p['review_count']} reseñas)'),
          _info('Horario', hours.isEmpty ? 'Sin horario configurado' : hours),
          const SizedBox(height: 4),
          const Text(
              'El nombre, la categoría y el costo de envío los define Express.',
              style: TextStyle(fontSize: 12, color: ExpressColors.textMuted)),
        ]),
      ),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Información',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _field('Descripción', _description, lines: 3),
          _field('Dirección', _address),
          Row(children: [
            Expanded(
                child: _field('Pedido mínimo ($currency)', _minimum,
                    type: TextInputType.number, hint: '0')),
            const SizedBox(width: 12),
            Expanded(
                child: _field('Preparación mín. (min)', _etaMin,
                    type: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(
                child: _field('Preparación máx. (min)', _etaMax,
                    type: TextInputType.number)),
          ]),
          _ImageUploadField(
              controller: _image, label: 'Logo', enabled: _canEdit),
          const SizedBox(height: 14),
          _ImageUploadField(
              controller: _cover, label: 'Portada', enabled: _canEdit),
          const SizedBox(height: 14),
          _field('Instrucciones de pago por transferencia', _transfer, lines: 3,
              hint: 'Banco, cuenta, titular…'),
          if (_canEdit)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Guardar cambios'),
              ),
            ),
        ]),
      ),
    ]);
  }
}

/// Imagen que se elige de la galería (o del computador) y se sube sola al depósito público
/// de imágenes de restaurantes; deja la dirección en [controller].
class _ImageUploadField extends StatefulWidget {
  const _ImageUploadField({
    required this.controller,
    required this.label,
    required this.enabled,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  State<_ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<_ImageUploadField> {
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

// ───────────────────────────── Horarios ─────────────────────────────

class RestaurantHoursPage extends StatefulWidget {
  const RestaurantHoursPage({super.key, required this.merchantId});
  final String merchantId;

  @override
  State<RestaurantHoursPage> createState() => _RestaurantHoursPageState();
}

class _RestaurantHoursPageState extends State<RestaurantHoursPage> {
  Map<String, List<({String from, String to})>>? _hours;
  bool _canEdit = false;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _hours = null;
      _error = null;
    });
    try {
      final p = _asMap(await _rpc(
          'marketplace_merchant_profile', {'p_merchant_id': widget.merchantId}));
      if (!mounted) return;
      final role = p['role']?.toString();
      setState(() {
        _canEdit = role == 'owner' || role == 'manager';
        _hours = parseBusinessHours(p['business_hours']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _pick(String day, int index, bool isFrom) async {
    final list = _hours![day]!;
    final current = isFrom ? list[index].from : list[index].to;
    final parts = current.split(':');
    final initial = TimeOfDay(
        hour: int.tryParse(parts.first) ?? 9,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    final picked = await showTimePicker(
        context: context,
        initialTime: initial,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!));
    if (picked == null) return;
    final text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      list[index] = isFrom
          ? (from: text, to: list[index].to)
          : (from: list[index].from, to: text);
    });
  }

  Future<void> _save() async {
    // Cada tramo debe terminar después de empezar (un tramo que cruza la medianoche
    // se carga como dos días).
    for (final day in businessHourDayKeys) {
      for (final r in _hours![day]!) {
        if (r.from.compareTo(r.to) >= 0) {
          _snack(context,
              '${businessHourDayNames[day]}: la hora de cierre debe ser posterior a la de apertura.');
          return;
        }
      }
    }
    setState(() => _saving = true);
    try {
      await _rpc('marketplace_merchant_update_hours', {
        'p_merchant_id': widget.merchantId,
        'p_hours': businessHoursToJson(_hours!),
      });
      _snack(context, 'Horarios guardados.');
    } catch (e) {
      _snack(context, _err(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _copyToOthers(String day) {
    final source = _hours![day]!;
    setState(() {
      for (final d in businessHourDayKeys) {
        if (d != day) _hours![d] = List.of(source);
      }
    });
    _snack(context, 'Horario de ${businessHourDayNames[day]} copiado a los demás días.');
  }

  @override
  Widget build(BuildContext context) {
    final hours = _hours;
    if (hours == null) {
      return _loadingOrError(
          loading: _error == null, error: _error, retry: _load);
    }
    return _PageFrame(maxWidth: 760, children: [
      _title('Horarios',
          sub: 'Tus clientes ven estos horarios. Un día sin tramos aparece cerrado.'),
      for (final day in businessHourDayKeys)
        _Panel(
          padding: 14,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(businessHourDayNames[day]!,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800))),
              if (_canEdit) ...[
                Switch(
                  value: hours[day]!.isNotEmpty,
                  onChanged: (on) => setState(() => hours[day] = on
                      ? [(from: '09:00', to: '22:00')]
                      : <({String from, String to})>[]),
                ),
              ],
            ]),
            if (hours[day]!.isEmpty)
              const Text('Cerrado',
                  style: TextStyle(color: ExpressColors.textMuted))
            else
              for (var i = 0; i < hours[day]!.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    OutlinedButton(
                        onPressed: _canEdit ? () => _pick(day, i, true) : null,
                        child: Text(hours[day]![i].from)),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('a')),
                    OutlinedButton(
                        onPressed: _canEdit ? () => _pick(day, i, false) : null,
                        child: Text(hours[day]![i].to)),
                    if (_canEdit && hours[day]!.length > 1)
                      IconButton(
                          tooltip: 'Quitar tramo',
                          onPressed: () =>
                              setState(() => hours[day]!.removeAt(i)),
                          icon: const Icon(Icons.close)),
                  ]),
                ),
            if (_canEdit && hours[day]!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 8, children: [
                  if (hours[day]!.length < 4)
                    TextButton.icon(
                        onPressed: () => setState(() =>
                            hours[day]!.add((from: '18:00', to: '22:00'))),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar tramo')),
                  TextButton.icon(
                      onPressed: () => _copyToOthers(day),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copiar a los demás días')),
                ]),
              ),
          ]),
        ),
      if (_canEdit)
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar horarios'),
          ),
        ),
    ]);
  }
}

// ───────────────────────────── Categorías ─────────────────────────────

class RestaurantCategoriesPage extends StatefulWidget {
  const RestaurantCategoriesPage({super.key, required this.merchantId});
  final String merchantId;

  @override
  State<RestaurantCategoriesPage> createState() =>
      _RestaurantCategoriesPageState();
}

class _RestaurantCategoriesPageState extends State<RestaurantCategoriesPage> {
  List<Map<String, dynamic>>? _cats;
  bool _canEdit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<dynamic>([
        _rpc('marketplace_merchant_categories_all',
            {'p_merchant_id': widget.merchantId}),
        _rpc('marketplace_merchant_profile', {'p_merchant_id': widget.merchantId}),
      ]);
      if (!mounted) return;
      final role = _asMap(results[1])['role']?.toString();
      setState(() {
        _cats = _asList(results[0]);
        _canEdit = role == 'owner' || role == 'manager';
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _edit(Map<String, dynamic>? cat) async {
    final controller = TextEditingController(text: cat?['name']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(cat == null ? 'Nueva categoría' : 'Renombrar categoría'),
        content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (ok != true) return;
    try {
      await _rpc('marketplace_merchant_upsert_category', {
        'p_merchant_id': widget.merchantId,
        'p_category_id': cat?['id'],
        'p_name': name,
      });
      await _load();
    } catch (e) {
      _snack(context, _err(e));
    }
  }

  Future<void> _toggle(Map<String, dynamic> cat, bool active) async {
    try {
      await _rpc('marketplace_merchant_set_category_active', {
        'p_merchant_id': widget.merchantId,
        'p_category_id': cat['id'],
        'p_active': active,
      });
      setState(() => cat['active'] = active);
    } catch (e) {
      _snack(context, _err(e));
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final cats = _cats!;
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() => cats.insert(newIndex, cats.removeAt(oldIndex)));
    try {
      await _rpc('marketplace_merchant_set_categories_order', {
        'p_merchant_id': widget.merchantId,
        'p_ids': [for (final c in cats) c['id']],
      });
    } catch (e) {
      _snack(context, _err(e));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    if (cats == null) {
      return _loadingOrError(
          loading: _error == null, error: _error, retry: _load);
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: _title('Categorías de productos',
                        sub: _canEdit
                            ? 'Organiza tu menú. Arrastra para cambiar el orden.'
                            : 'Solo el dueño o el encargado pueden editar las categorías.')),
                if (_canEdit)
                  FilledButton.icon(
                      onPressed: () => _edit(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva categoría')),
              ]),
              if (cats.isEmpty)
                const _Panel(
                    child: Text('Todavía no tienes categorías. Crea la primera.'))
              else
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: _canEdit,
                  onReorder: _canEdit ? _reorder : (_, __) {},
                  children: [
                    for (final c in cats)
                      Container(
                        key: ValueKey(c['id']),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: ExpressColors.surface,
                          border: Border.all(color: ExpressColors.border),
                          borderRadius: BorderRadius.circular(ExpressRadii.card),
                        ),
                        child: ListTile(
                          title: Text(c['name']?.toString() ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${c['product_count'] ?? 0} producto${(c['product_count'] ?? 0) == 1 ? '' : 's'}'
                              '${c['active'] == false ? ' · oculta' : ''}'),
                          trailing: _canEdit
                              ? Row(mainAxisSize: MainAxisSize.min, children: [
                                  Switch(
                                      value: c['active'] != false,
                                      onChanged: (v) => _toggle(c, v)),
                                  IconButton(
                                      tooltip: 'Renombrar',
                                      onPressed: () => _edit(c),
                                      icon: const Icon(Icons.edit_outlined)),
                                  const SizedBox(width: 28),
                                ])
                              : null,
                        ),
                      ),
                  ],
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── Reportes ─────────────────────────────

class RestaurantReportsPage extends StatefulWidget {
  const RestaurantReportsPage({super.key, required this.merchantId});
  final String merchantId;

  @override
  State<RestaurantReportsPage> createState() => _RestaurantReportsPageState();
}

class _RestaurantReportsPageState extends State<RestaurantReportsPage> {
  int _days = 30;
  String _group = 'day';
  Map<String, dynamic>? _data;
  String _currency = 'BOB';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final to = DateTime.now();
      final from = to.subtract(Duration(days: _days - 1));
      final results = await Future.wait<dynamic>([
        _rpc('marketplace_merchant_report', {
          'p_merchant_id': widget.merchantId,
          'p_from': _iso(from),
          'p_to': _iso(to),
          'p_group': _group,
        }),
        _rpc('marketplace_merchant_profile', {'p_merchant_id': widget.merchantId}),
      ]);
      if (!mounted) return;
      setState(() {
        _data = _asMap(results[0]);
        _currency = _asMap(results[1])['currency']?.toString() ?? 'BOB';
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  void _exportCsv() {
    final rows = _asList(_data?['orders']);
    String esc(Object? v) {
      final t = (v ?? '').toString().replaceAll('"', '""');
      return '"$t"';
    }

    final b = StringBuffer('Pedido,Fecha,Estado,Pago,Total,Productos\n');
    for (final o in rows) {
      b.writeln([
        esc(o['id']?.toString().substring(0, 8).toUpperCase()),
        esc(o['created_at']),
        esc(_statusLabel(o['status']?.toString() ?? '')),
        esc(o['payment_method']),
        esc(o['total_amount']),
        esc(o['products_amount']),
      ].join(','));
    }
    restaurantDownloadText('reporte-pedidos-${_iso(DateTime.now())}.csv', b.toString());
    _snack(context, rows.isEmpty ? 'No hay pedidos en el periodo.' : 'Reporte descargado.');
  }

  String _statusLabel(String s) => switch (s) {
        'delivered' => 'Entregado',
        'cancelled' => 'Cancelado',
        'preparing' => 'Preparando',
        'ready' => 'Listo',
        'confirmed' => 'Confirmado',
        _ => 'En curso',
      };

  Widget _kpi(String label, String value) => Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ExpressColors.surface,
          border: Border.all(color: ExpressColors.border),
          borderRadius: BorderRadius.circular(ExpressRadii.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 12, color: ExpressColors.textMuted)),
        ]),
      );

  Widget _bars(List<({String label, double value, String text})> items,
      {Color color = ExpressColors.blue}) {
    if (items.isEmpty) {
      return const Text('No hay datos para el periodo seleccionado.',
          style: TextStyle(color: ExpressColors.textMuted));
    }
    final max = items.map((e) => e.value).fold<double>(0, (a, b) => b > a ? b : a);
    return Column(children: [
      for (final i in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
                width: 110,
                child: Text(i.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12))),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 16,
                    width: max <= 0 ? 2 : (c.maxWidth * (i.value / max)).clamp(2, c.maxWidth),
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            SizedBox(
                width: 90,
                child: Text(i.text,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return _loadingOrError(
          loading: _error == null, error: _error, retry: _load);
    }
    final t = _asMap(d['totals']);
    final series = _asList(d['series']);
    final top = _asList(d['top_products']);
    final byHour = _asList(d['by_hour']);
    double n(Object? v) => double.tryParse(v?.toString() ?? '') ?? 0;
    return _PageFrame(maxWidth: 1000, children: [
      Row(children: [
        Expanded(
            child: _title('Reportes y analíticas',
                sub: 'Ventas y pedidos de tu restaurante.')),
        OutlinedButton.icon(
            onPressed: _exportCsv,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Exportar CSV')),
      ]),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final days in [7, 30, 90])
          ChoiceChip(
              label: Text('$days días'),
              selected: _days == days,
              onSelected: (_) {
                _days = days;
                _load();
              }),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _group,
          items: const [
            DropdownMenuItem(value: 'day', child: Text('Por día')),
            DropdownMenuItem(value: 'week', child: Text('Por semana')),
            DropdownMenuItem(value: 'month', child: Text('Por mes')),
          ],
          onChanged: (v) {
            if (v == null) return;
            _group = v;
            _load();
          },
        ),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _kpi('Total de pedidos', '${t['orders'] ?? 0}'),
        _kpi('Ventas totales', expressMoney(t['sales'] ?? 0, _currency)),
        _kpi('Ticket promedio', expressMoney(t['average_ticket'] ?? 0, _currency)),
        _kpi('Propinas', expressMoney(t['tips'] ?? 0, _currency)),
        _kpi('Artículos vendidos', '${t['items'] ?? 0}'),
        _kpi('Tasa de completados', '${t['completion_rate'] ?? 0}%'),
      ]),
      const SizedBox(height: 18),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ventas por periodo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _bars([
            for (final s in series)
              (
                label: s['period']?.toString() ?? '',
                value: n(s['sales']),
                text: expressMoney(s['sales'] ?? 0, _currency)
              ),
          ]),
        ]),
      ),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Productos más vendidos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _bars([
            for (final p in top)
              (
                label: p['name']?.toString() ?? '',
                value: n(p['quantity']),
                text: '${p['quantity']} uds.'
              ),
          ], color: ExpressColors.mint),
        ]),
      ),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pedidos por hora',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _bars([
            for (final h in byHour)
              (
                label: '${h['hour'].toString().padLeft(2, '0')}:00',
                value: n(h['orders']),
                text: '${h['orders']}'
              ),
          ], color: ExpressColors.amber),
        ]),
      ),
    ]);
  }
}

// ───────────────────────────── Reseñas ─────────────────────────────

class RestaurantReviewsPage extends StatefulWidget {
  const RestaurantReviewsPage({super.key, required this.merchantId});
  final String merchantId;

  @override
  State<RestaurantReviewsPage> createState() => _RestaurantReviewsPageState();
}

class _RestaurantReviewsPageState extends State<RestaurantReviewsPage> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final d = _asMap(await _rpc(
          'marketplace_merchant_reviews', {'p_merchant_id': widget.merchantId}));
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Widget _stars(int n) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= n ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 18, color: ExpressColors.amber),
      ]);

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return _loadingOrError(
          loading: _error == null, error: _error, retry: _load);
    }
    final summary = _asMap(d['summary']);
    final reviews = _asList(d['reviews']);
    final count = int.tryParse('${summary['count'] ?? 0}') ?? 0;
    return _PageFrame(maxWidth: 760, children: [
      _title('Reseñas',
          sub: 'Lo que tus clientes dicen de tu restaurante. El promedio se calcula solo con reseñas reales.'),
      _Panel(
        child: Row(children: [
          Text(count == 0 ? '—' : '${summary['average']}',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Text(count == 0
              ? 'Aún no tienes reseñas'
              : '$count reseña${count == 1 ? '' : 's'}'),
        ]),
      ),
      if (reviews.isEmpty)
        const _Panel(
            child: Text(
                'Cuando tus clientes califiquen sus pedidos entregados, sus reseñas aparecerán aquí.',
                style: TextStyle(color: ExpressColors.textMuted)))
      else
        for (final r in reviews)
          _Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _stars(int.tryParse('${r['rating']}') ?? 0),
                const Spacer(),
                Text(
                    (r['created_at']?.toString() ?? '').split('T').first,
                    style: const TextStyle(
                        fontSize: 12, color: ExpressColors.textMuted)),
              ]),
              if ((r['comment']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(r['comment'].toString()),
              ],
            ]),
          ),
    ]);
  }
}

// ───────────────────────────── Soporte ─────────────────────────────

/// Chat con el equipo de Express (usa la misma bandeja de soporte de la app).
class RestaurantSupportPage extends StatefulWidget {
  const RestaurantSupportPage({super.key, required this.service});
  final ExpressService service;

  @override
  State<RestaurantSupportPage> createState() => _RestaurantSupportPageState();
}

class _RestaurantSupportPageState extends State<RestaurantSupportPage> {
  List<Map<String, dynamic>> _messages = const [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _loaded = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final rows = await widget.service.supportMessages();
      if (!mounted) return;
      final grew = rows.length != _messages.length;
      setState(() {
        _messages = rows;
        _loaded = true;
        _error = null;
      });
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted && !quiet) {
        setState(() {
          _error = _err(e);
          _loaded = true;
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.service.sendSupportMessage(text);
      _input.clear();
      await _load();
    } catch (e) {
      _snack(context, _err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Align(
                alignment: Alignment.centerLeft,
                child: _title('Soporte',
                    sub: 'Escribe al equipo de Express. Te respondemos aquí.')),
          ),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, textAlign: TextAlign.center)),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('Aún no hay mensajes. Cuéntanos en qué te ayudamos.',
                        style: TextStyle(color: ExpressColors.textMuted)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final mine = m['sender_role'] == 'user';
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: mine
                                ? ExpressColors.blue
                                : ExpressColors.surface,
                            border: mine
                                ? null
                                : Border.all(color: ExpressColors.border),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(m['body']?.toString() ?? '',
                              style: TextStyle(
                                  color: mine ? Colors.white : ExpressColors.text)),
                        ),
                      );
                    }),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Escribe tu mensaje…'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ]),
      ),
    );
  }
}

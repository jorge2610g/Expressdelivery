import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'design/express_tokens.dart';
import 'map_provider.dart';
import 'money_format.dart';

Future<dynamic> _rpc(String fn, Map<String, dynamic> params) => supabase.rpc(
      fn,
      params: {...params, 'p_channel': ExpressRuntimeChannel.name},
    );

String _err(Object e) => ExpressRuntimeChannel.userSafeError(e,
    fallback: 'No se pudo completar la acción. Intenta de nuevo.');

/// Perfil de un local que solo usa «Solicitar repartidor»: nombre, correo, costo del
/// delivery y la ubicación predeterminada desde donde sale el repartidor.
class RestaurantCourierProfilePage extends StatefulWidget {
  const RestaurantCourierProfilePage({
    super.key,
    required this.merchantId,
    this.debugProfile,
    this.debugEmail,
  });
  final String merchantId;

  /// Solo para pruebas y capturas: datos fijos, sin llamadas al servidor.
  final Map<String, dynamic>? debugProfile;
  final String? debugEmail;

  @override
  State<RestaurantCourierProfilePage> createState() =>
      _RestaurantCourierProfilePageState();
}

class _RestaurantCourierProfilePageState
    extends State<RestaurantCourierProfilePage> {
  final _address = TextEditingController();
  final _map = MapController();
  Map<String, dynamic>? _p;
  String? _error;
  LatLng? _point;
  bool _saving = false;
  bool _changed = false;
  List<({String label, double latitude, double longitude})> _suggestions = const [];
  Timer? _searchTimer;
  int _searchRevision = 0;
  bool _searching = false;
  String? _searchNote;

  bool get _canEdit {
    final role = _p?['role']?.toString();
    return role == 'owner' || role == 'manager';
  }

  String get _country =>
      (_p?['country_code']?.toString() ?? 'BO').toLowerCase();

  String get _email {
    if (widget.debugEmail != null) return widget.debugEmail!;
    try {
      return supabase.auth.currentUser?.email ?? '—';
    } catch (_) {
      return '—';
    }
  }

  LatLng get _fallbackCenter => _country == 'cl'
      ? const LatLng(-20.2307, -70.1357)
      : const LatLng(-16.5, -68.15);

  @override
  void initState() {
    super.initState();
    if (widget.debugProfile != null) {
      _apply(widget.debugProfile!);
      return;
    }
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _address.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> p) {
    _p = p;
    _address.text = p['address']?.toString() ?? '';
    final lat = double.tryParse(p['latitude']?.toString() ?? '');
    final lng = double.tryParse(p['longitude']?.toString() ?? '');
    _point = (lat != null && lng != null) ? LatLng(lat, lng) : null;
  }

  Future<void> _load() async {
    setState(() {
      _p = null;
      _error = null;
    });
    try {
      final raw = await _rpc(
          'marketplace_merchant_profile', {'p_merchant_id': widget.merchantId});
      if (!mounted) return;
      setState(() {
        _apply(Map<String, dynamic>.from(raw as Map));
        _changed = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  void _onAddressChanged(String text) {
    if (!_canEdit) return;
    _searchTimer?.cancel();
    final query = text.trim();
    if (query.length < 3) {
      _searchRevision++;
      setState(() {
        _suggestions = const [];
        _searching = false;
        _searchNote = null;
      });
      return;
    }
    final revision = ++_searchRevision;
    setState(() {
      _searching = true;
      _searchNote = null;
    });
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      List<({String label, double latitude, double longitude})> results = const [];
      try {
        results = await ExpressMapProvider.searchAddress(
            query: query, countryCode: _country, proximity: _point ?? _fallbackCenter);
      } catch (_) {}
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _suggestions = results;
        _searching = false;
        _searchNote = results.isEmpty
            ? 'No encontramos esa dirección. Prueba con otra escritura o toca el mapa para marcar el punto.'
            : null;
      });
    });
  }

  Future<void> _setPoint(LatLng point, {String? label}) async {
    setState(() {
      _point = point;
      _changed = true;
      _suggestions = const [];
      _searching = false;
      _searchNote = null;
      if (label != null) _address.text = label;
    });
    _map.move(point, 16);
    if (label == null) {
      final found = await ExpressMapProvider.reverseGeocode(
          point: point, countryCode: _country);
      if (mounted && _point == point) {
        setState(() => _address.text = found ?? 'Punto seleccionado en el mapa');
      }
    }
  }

  Future<void> _save() async {
    final point = _point;
    if (point == null) return;
    setState(() => _saving = true);
    try {
      await _rpc('marketplace_merchant_set_location', {
        'p_merchant_id': widget.merchantId,
        'p_address': _address.text,
        'p_latitude': point.latitude,
        'p_longitude': point.longitude,
      });
      if (!mounted) return;
      setState(() => _changed = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ubicación guardada.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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

  Widget _panel(List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ExpressColors.surface,
          border: Border.all(color: ExpressColors.border),
          borderRadius: BorderRadius.circular(ExpressRadii.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  String _deliveryCost(Map<String, dynamic> p) {
    final currency = p['currency']?.toString() ?? 'BOB';
    final flat = double.tryParse(p['courier_flat_fare']?.toString() ?? '');
    if (p['courier_pricing'] == 'flat' && flat != null && flat > 0) {
      return '${expressMoney(flat, currency)} por envío (precio fijo)';
    }
    return 'Se calcula por la ruta: distancia y tiempo';
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      if (_error == null) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar')),
        ]),
      );
    }
    final center = _point ?? _fallbackCenter;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Mi local',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Datos con los que solicitas repartidores.',
                style: TextStyle(color: ExpressColors.textMuted)),
            const SizedBox(height: 16),
            _panel([
              _info('Nombre del local', p['name']?.toString() ?? '—'),
              _info('Correo', _email),
              _info('Costo del delivery', _deliveryCost(p)),
              const SizedBox(height: 4),
              const Text(
                  'El nombre y el costo del delivery los define Express. Si necesitas cambiarlos, escríbenos desde Soporte.',
                  style: TextStyle(fontSize: 12, color: ExpressColors.textMuted)),
            ]),
            _panel([
              const Text('Ubicación predeterminada del local',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  _canEdit
                      ? 'Desde aquí sale el repartidor. Busca la dirección o toca el mapa para marcar el punto.'
                      : 'Solo el dueño o el encargado pueden cambiar la ubicación.',
                  style: const TextStyle(color: ExpressColors.textMuted, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                enabled: _canEdit,
                onChanged: _onAddressChanged,
                decoration: const InputDecoration(
                    labelText: 'Dirección del local',
                    prefixIcon: Icon(Icons.search)),
              ),
              if (_searching || _searchNote != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 6),
                  child: Row(children: [
                    if (_searching)
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    if (_searching) const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          _searching ? 'Buscando direcciones…' : _searchNote!,
                          style: const TextStyle(
                              fontSize: 12.5, color: ExpressColors.textMuted)),
                    ),
                  ]),
                ),
              for (final s in _suggestions)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(s.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _setPoint(LatLng(s.latitude, s.longitude), label: s.label),
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ExpressRadii.card),
                  child: widget.debugProfile != null
                      ? Container(
                          color: ExpressColors.raised,
                          alignment: Alignment.center,
                          child: const Text('Mapa'))
                      : FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: _point == null ? 12 : 16,
                            onTap: _canEdit ? (_, pt) => _setPoint(pt) : null,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'online.expressviajes',
                            ),
                            if (_point != null)
                              MarkerLayer(markers: [
                                Marker(
                                  point: _point!,
                                  width: 44,
                                  height: 52,
                                  alignment: Alignment.topCenter,
                                  child: const Icon(Icons.location_pin,
                                      size: 44, color: ExpressColors.coral),
                                ),
                              ]),
                          ],
                        ),
                ),
              ),
              if (_point == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Todavía no hay una ubicación guardada.',
                      style: TextStyle(color: ExpressColors.coral, fontSize: 13)),
                ),
              if (_canEdit)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton.icon(
                      onPressed: (_saving || !_changed || _point == null) ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: const Text('Guardar ubicación'),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    ]);
  }
}

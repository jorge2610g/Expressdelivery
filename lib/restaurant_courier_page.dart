import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// «Solicitar repartidor»: el restaurante pide un repartidor para un cliente que pidió
/// por teléfono o WhatsApp. El sistema calcula la ruta y la tarifa; el repartidor ve las
/// instrucciones en su app. Restaurante y repartidor se pagan entre ellos.
class RestaurantCourierPage extends StatefulWidget {
  const RestaurantCourierPage({
    super.key,
    required this.merchantId,
    this.onSent,
    this.debugProfile,
  });
  final String merchantId;

  /// Se llama al enviar una solicitud, para llevar al restaurante a «Mis solicitudes».
  final VoidCallback? onSent;

  /// Solo para capturas de diseño: perfil fijo, sin llamadas al servidor.
  final Map<String, dynamic>? debugProfile;

  @override
  State<RestaurantCourierPage> createState() => _RestaurantCourierPageState();
}

class _RestaurantCourierPageState extends State<RestaurantCourierPage> {
  Map<String, dynamic>? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.debugProfile != null) {
      _profile = widget.debugProfile;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _profile = null;
      _error = null;
    });
    try {
      final p = await _rpc(
          'marketplace_merchant_profile', {'p_merchant_id': widget.merchantId});
      if (mounted) setState(() => _profile = Map<String, dynamic>.from(p as Map));
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
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
    final hasLocation = p['latitude'] != null && p['longitude'] != null;
    if (!hasLocation) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'Tu local no tiene una ubicación guardada. Márcala en «Perfil» para poder solicitar repartidores.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return _CourierForm(
      merchantId: widget.merchantId,
      profile: p,
      onSent: widget.onSent ?? () {},
      placeholderMap: widget.debugProfile != null,
    );
  }
}

class _CourierForm extends StatefulWidget {
  const _CourierForm({
    required this.merchantId,
    required this.profile,
    required this.onSent,
    this.placeholderMap = false,
  });
  final String merchantId;
  final Map<String, dynamic> profile;
  final VoidCallback onSent;

  /// Solo capturas de diseño: sin mapa real (no hay red ni plugins en las pruebas).
  final bool placeholderMap;

  @override
  State<_CourierForm> createState() => _CourierFormState();
}

class _CourierFormState extends State<_CourierForm> {
  final _customerPhone = TextEditingController();
  final _customerName = TextEditingController();
  final _address = TextEditingController();
  final _collect = TextEditingController();
  final _changeFor = TextEditingController();
  final _notes = TextEditingController();
  final _senderPhone = TextEditingController();
  final _map = MapController();

  String _serviceType = 'collect';
  String _payment = 'cash';
  int _prep = 15;

  LatLng? _destination;
  List<LatLng> _route = const [];
  double? _km;
  double? _minutes;
  double? _fee;
  String? _quoteError;
  bool _routing = false;
  bool _sending = false;

  List<({String label, double latitude, double longitude})> _suggestions = const [];
  Timer? _searchTimer;
  int _searchRevision = 0;
  bool _searching = false;
  String? _searchNote;

  LatLng get _origin => LatLng(
      double.parse(widget.profile['latitude'].toString()),
      double.parse(widget.profile['longitude'].toString()));
  String get _country =>
      (widget.profile['country_code']?.toString() ?? 'BO').toLowerCase();
  String get _currency => widget.profile['currency']?.toString() ?? 'BOB';
  bool get _flat => widget.profile['courier_pricing'] == 'flat';

  @override
  void initState() {
    super.initState();
    _customerPhone.text = _country == 'cl' ? '+56 ' : '+591 ';
    _loadSenderPhone();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    for (final c in [
      _customerPhone, _customerName, _address, _collect, _changeFor, _notes, _senderPhone
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSenderPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('restaurant_phone_${widget.merchantId}');
      if (saved != null && mounted) _senderPhone.text = saved;
    } catch (_) {}
  }

  void _onAddressChanged(String text) {
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
            query: query, countryCode: _country, proximity: _origin);
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

  Future<void> _setDestination(LatLng point, {String? label}) async {
    setState(() {
      _destination = point;
      _suggestions = const [];
      _searching = false;
      _searchNote = null;
      _route = const [];
      _km = null;
      _minutes = null;
      _fee = null;
      _quoteError = null;
      _routing = true;
      if (label != null) _address.text = label;
    });
    if (label == null) {
      final found = await ExpressMapProvider.reverseGeocode(
          point: point, countryCode: _country);
      if (mounted && _destination == point) {
        setState(() => _address.text = found ?? 'Punto seleccionado en el mapa');
      }
    }
    try {
      final route = await ExpressMapProvider.drivingRoute(from: _origin, to: point);
      if (!mounted || _destination != point) return;
      final meters = route.distanceMeters;
      final seconds = route.durationSeconds;
      if (meters == null || meters <= 0) {
        setState(() {
          _route = route.points;
          _routing = false;
          _quoteError = 'No se pudo calcular la ruta. Elige otro punto o intenta de nuevo.';
        });
        return;
      }
      _km = meters / 1000;
      _minutes = ((seconds ?? 0) / 60).clamp(1, 600).toDouble();
      setState(() => _route = route.points);
      final quote = await _rpc('marketplace_merchant_courier_quote', {
        'p_merchant_id': widget.merchantId,
        'p_dest_lat': point.latitude,
        'p_dest_lng': point.longitude,
        'p_distance_km': double.parse(_km!.toStringAsFixed(3)),
        'p_duration_min': double.parse(_minutes!.toStringAsFixed(1)),
      });
      if (!mounted || _destination != point) return;
      setState(() {
        _fee = double.tryParse('${(quote as Map)['fee']}');
        _routing = false;
      });
      _fitMap();
    } catch (e) {
      if (mounted && _destination == point) {
        setState(() {
          _routing = false;
          _quoteError = _err(e);
        });
      }
    }
  }

  void _fitMap() {
    final d = _destination;
    if (d == null) return;
    try {
      _map.fitCamera(CameraFit.coordinates(
          coordinates: [_origin, d, ..._route],
          padding: const EdgeInsets.all(40)));
    } catch (_) {}
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    final dest = _destination;
    if (dest == null || _km == null || _fee == null) {
      _msg('Elige la dirección de entrega en el mapa.');
      return;
    }
    if (_serviceType == 'collect' && (_num(_collect) ?? 0) <= 0) {
      _msg('Escribe el monto a cobrar.');
      return;
    }
    setState(() => _sending = true);
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'restaurant_phone_${widget.merchantId}', _senderPhone.text.trim());
      } catch (_) {}
      await _rpc('marketplace_merchant_request_courier', {
        'p_merchant_id': widget.merchantId,
        'p_customer_name': _customerName.text,
        'p_customer_phone': _customerPhone.text,
        'p_dest_address': _address.text,
        'p_dest_lat': dest.latitude,
        'p_dest_lng': dest.longitude,
        'p_distance_km': double.parse(_km!.toStringAsFixed(3)),
        'p_duration_min': double.parse((_minutes ?? 1).toStringAsFixed(1)),
        'p_service_type': _serviceType,
        'p_collect_amount': _serviceType == 'collect' ? _num(_collect) : null,
        'p_customer_payment': _payment,
        'p_change_for': _serviceType == 'collect' && _payment == 'cash'
            ? _num(_changeFor)
            : null,
        'p_prep_minutes': _prep,
        'p_notes': _notes.text,
        'p_sender_phone': _senderPhone.text,
      });
      if (!mounted) return;
      _msg('Solicitud enviada. Estamos buscando un repartidor.');
      setState(() {
        _customerName.clear();
        _address.clear();
        _collect.clear();
        _changeFor.clear();
        _notes.clear();
        _destination = null;
        _route = const [];
        _km = null;
        _minutes = null;
        _fee = null;
      });
      widget.onSent();
    } catch (e) {
      _msg(_err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _section(String title, List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ExpressColors.surface,
          border: Border.all(color: ExpressColors.border),
          borderRadius: BorderRadius.circular(ExpressRadii.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _summary() {
    final fee = _fee;
    if (_routing) {
      return const Row(children: [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 10),
        Text('Calculando la ruta y la tarifa…'),
      ]);
    }
    if (_quoteError != null) {
      return Text(_quoteError!, style: const TextStyle(color: ExpressColors.coral));
    }
    if (fee == null) {
      return const Text('Elige la dirección de entrega para ver la ruta y el delivery.',
          style: TextStyle(color: ExpressColors.textMuted));
    }
    final collect = _num(_collect) ?? 0;
    final lines = <String>[
      'Distancia: ${_km!.toStringAsFixed(1)} km · ${_minutes!.round()} min',
      'Delivery: ${expressMoney(fee, _currency)}${_flat ? ' (tarifa fija de tu restaurante)' : ''}',
      if (_serviceType == 'collect' && collect > fee)
        'El repartidor te pagará ${expressMoney(collect - fee, _currency)} al retirar y cobrará ${expressMoney(collect, _currency)} al cliente.'
      else if (_serviceType == 'deliver_only')
        'Tú le pagas el delivery (${expressMoney(fee, _currency)}) al repartidor.',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final l in lines)
        Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(l)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Solicitar repartidor',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 14),
              child: Text(
                  'Para pedidos de clientes que te escriben o llaman. Express conecta a tu restaurante con un repartidor; el pago se hace entre ustedes.',
                  style: TextStyle(color: ExpressColors.textMuted)),
            ),
            _section('Cliente', [
              TextField(
                controller: _customerPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono del cliente'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customerName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre del cliente *'),
              ),
            ]),
            _section('Entrega', [
              TextField(
                controller: _address,
                onChanged: _onAddressChanged,
                decoration: const InputDecoration(
                    labelText: 'Dirección de entrega *',
                    prefixIcon: Icon(Icons.search),
                    helperText: 'Escribe la dirección o toca el mapa para marcar el punto.'),
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
                  onTap: () =>
                      _setDestination(LatLng(s.latitude, s.longitude), label: s.label),
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 320,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ExpressRadii.card),
                  child: widget.placeholderMap
                      ? Container(
                          color: ExpressColors.raised,
                          alignment: Alignment.center,
                          child: const Text('Mapa'),
                        )
                      : FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _origin,
                      initialZoom: 15,
                      onTap: (_, point) => _setDestination(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'online.expressviajes',
                      ),
                      if (_route.length > 1)
                        PolylineLayer(polylines: [
                          Polyline(
                              points: _route,
                              strokeWidth: 5,
                              color: ExpressColors.blue),
                        ]),
                      MarkerLayer(markers: [
                        Marker(
                          point: _origin,
                          width: 44,
                          height: 44,
                          child: const Icon(Icons.storefront_rounded,
                              size: 34, color: ExpressColors.blue),
                        ),
                        if (_destination != null)
                          Marker(
                            point: _destination!,
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
              const SizedBox(height: 12),
              _summary(),
            ]),
            _section('Tipo de servicio', [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'collect', label: Text('Entregar y cobrar')),
                  ButtonSegment(value: 'deliver_only', label: Text('Solo entregar')),
                ],
                selected: {_serviceType},
                onSelectionChanged: (v) => setState(() => _serviceType = v.first),
              ),
              const SizedBox(height: 8),
              Text(
                  _serviceType == 'collect'
                      ? 'Pedido contra entrega: el repartidor le paga al local el monto menos su delivery y cobra el monto completo al cliente.'
                      : 'El cliente ya pagó al local. Tú le pagas el delivery al repartidor.',
                  style: const TextStyle(color: ExpressColors.textMuted, fontSize: 13)),
              if (_serviceType == 'collect') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _collect,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: 'Monto a cobrar al cliente ($_currency) *'),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  for (final (key, label) in [
                    ('cash', 'Efectivo'),
                    ('card', 'Tarjeta'),
                    ('other', 'Otro / billetera'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _payment == key,
                      onSelected: (_) => setState(() => _payment = key),
                    ),
                ]),
                if (_payment == 'cash') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _changeFor,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'Con cuánto paga el cliente ($_currency, opcional)',
                        helperText: 'Para que el repartidor lleve el cambio.'),
                  ),
                ],
              ],
            ]),
            _section('Preparación e instrucciones', [
              DropdownButtonFormField<int>(
                initialValue: _prep,
                decoration: const InputDecoration(labelText: 'Tiempo de preparación'),
                items: [
                  for (final m in [0, 5, 10, 15, 20, 30, 45, 60])
                    DropdownMenuItem(
                        value: m, child: Text(m == 0 ? 'Listo ahora' : '$m min')),
                ],
                onChanged: (v) => setState(() => _prep = v ?? 15),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _senderPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Teléfono del restaurante *',
                    helperText: 'El repartidor lo usa para contactarte.'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                maxLength: 400,
                decoration: const InputDecoration(
                    labelText: 'Nota para el repartidor (opcional)',
                    hintText: 'Referencias, piso, color del portón, mesa…'),
              ),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: (_sending || _routing) ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delivery_dining_rounded),
                label: const Text('Solicitar repartidor'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// Estado de una solicitud para los filtros de «Mis solicitudes».
enum CourierRequestFilter {
  all('Todas'),
  active('En proceso'),
  done('Completadas'),
  cancelled('Canceladas'),
  noDriver('Sin repartidor');

  const CourierRequestFilter(this.label);
  final String label;
}

/// Agrupa una solicitud (estado del viaje y del servicio) en uno de los filtros.
CourierRequestFilter courierRequestBucket(Map<String, dynamic> r) {
  final status = r['status']?.toString() ?? '';
  final trip = r['trip_status']?.toString();
  if (trip == 'completed') return CourierRequestFilter.done;
  if (trip == 'cancelled') return CourierRequestFilter.cancelled;
  if (trip != null) return CourierRequestFilter.active;
  if (status == 'cancelled') return CourierRequestFilter.cancelled;
  if (status == 'expired') return CourierRequestFilter.noDriver;
  return CourierRequestFilter.active;
}

/// «Mis solicitudes»: historial de repartidores pedidos, con filtros por estado.
class RestaurantCourierRequestsPage extends StatelessWidget {
  const RestaurantCourierRequestsPage(
      {super.key, required this.merchantId, this.debugRows});
  final String merchantId;

  /// Solo para pruebas: filas fijas, sin llamadas al servidor.
  final List<Map<String, dynamic>>? debugRows;

  @override
  Widget build(BuildContext context) =>
      _CourierRequests(merchantId: merchantId, debugRows: debugRows);
}

class _CourierRequests extends StatefulWidget {
  const _CourierRequests({required this.merchantId, this.debugRows});
  final String merchantId;

  /// Solo para pruebas: filas fijas, sin llamadas al servidor.
  final List<Map<String, dynamic>>? debugRows;

  @override
  State<_CourierRequests> createState() => _CourierRequestsState();
}

class _CourierRequestsState extends State<_CourierRequests> {
  // Al abrir se muestran siempre las pendientes (en proceso).
  CourierRequestFilter _filter = CourierRequestFilter.active;
  List<Map<String, dynamic>>? _rows;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.debugRows != null) {
      _rows = widget.debugRows;
      return;
    }
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final raw = await _rpc(
          'marketplace_merchant_courier_requests', {'p_merchant_id': widget.merchantId});
      if (!mounted) return;
      setState(() {
        _rows = (raw as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = _err(e));
    }
  }

  String _label(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? '';
    final trip = r['trip_status']?.toString();
    final driver = r['driver_name']?.toString();
    final who = (driver == null || driver.isEmpty) ? 'Repartidor' : driver;
    if (trip == 'completed') return 'Entregado';
    if (trip == 'cancelled' || (trip == null && status == 'cancelled')) return 'Cancelada';
    if (trip == null && status == 'expired') return 'Sin repartidor';
    if (trip == 'in_progress') return '$who va en camino al cliente';
    if (trip == 'driver_waiting') return '$who llegó al local';
    if (trip != null) return '$who va hacia el local';
    if (status == 'searching' || status == 'offers_received') return 'Buscando repartidor…';
    if (status == 'driver_selected') return '$who va hacia el local';
    return status;
  }

  Color _color(Map<String, dynamic> r) {
    final label = _label(r);
    if (label.startsWith('Cancelada') || label == 'Sin repartidor') {
      return ExpressColors.coral;
    }
    if (label == 'Entregado') return ExpressColors.mint;
    if (label.startsWith('Buscando')) return ExpressColors.amber;
    return ExpressColors.blue;
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar solicitud'),
        content: const Text('Se dejará de buscar un repartidor para este pedido.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancelar solicitud')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _rpc('marketplace_merchant_cancel_courier',
          {'p_merchant_id': widget.merchantId, 'p_request_id': r['id']});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) {
      if (_error == null) return const Center(child: CircularProgressIndicator());
      return Center(child: Text(_error!));
    }
    if (rows.isEmpty) {
      return const Center(
          child: Text('Todavía no has solicitado repartidores.',
              style: TextStyle(color: ExpressColors.textMuted)));
    }
    int count(CourierRequestFilter f) => f == CourierRequestFilter.all
        ? rows.length
        : rows.where((r) => courierRequestBucket(r) == f).length;
    final shown = _filter == CourierRequestFilter.all
        ? rows
        : rows.where((r) => courierRequestBucket(r) == _filter).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in CourierRequestFilter.values)
                    if (f == CourierRequestFilter.all ||
                        f == CourierRequestFilter.active ||
                        f == CourierRequestFilter.done ||
                        f == CourierRequestFilter.cancelled ||
                        count(f) > 0)
                      ChoiceChip(
                        label: Text('${f.label} (${count(f)})'),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                ]),
              ),
            ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                    _filter == CourierRequestFilter.active
                        ? 'No tienes solicitudes en proceso.'
                        : 'No hay solicitudes con este estado.',
                    style: const TextStyle(color: ExpressColors.textMuted)),
              ),
            for (final r in shown)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ExpressColors.surface,
                  border: Border.all(color: ExpressColors.border),
                  borderRadius: BorderRadius.circular(ExpressRadii.card),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(r['customer_name']?.toString() ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _color(r).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(ExpressRadii.pill),
                      ),
                      child: Text(_label(r),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _color(r))),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(r['destination_address']?.toString() ?? '',
                      style: const TextStyle(color: ExpressColors.textSoft)),
                  const SizedBox(height: 6),
                  Text(
                      '${r['service_type'] == 'collect' ? 'Entregar y cobrar ${expressMoney(r['collect_amount'], r['currency'])}' : 'Solo entregar'}'
                      ' · Delivery ${expressMoney(r['delivery_fee'], r['currency'])}'
                      ' · ${(r['created_at']?.toString() ?? '').replaceFirst('T', ' ').split('.').first}',
                      style: const TextStyle(fontSize: 12, color: ExpressColors.textMuted)),
                  if (r['status'] == 'searching' || r['status'] == 'offers_received')
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                          onPressed: () => _cancel(r),
                          child: const Text('Cancelar solicitud')),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    ]);
  }
}

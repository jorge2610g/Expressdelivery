import 'package:flutter/material.dart';

import 'core/supabase_client.dart';

const Color _blue = Color(0xFF0B57D0);
const Color _dark = Color(0xFF101828);
const Color _muted = Color(0xFF667085);

class AdminZonesPage extends StatefulWidget {
  const AdminZonesPage({super.key});

  @override
  State<AdminZonesPage> createState() => _AdminZonesPageState();
}

class _AdminZonesPageState extends State<AdminZonesPage> {
  int revision = 0;

  Future<List<Map<String, dynamic>>> _load() async {
    final value = await supabase.rpc('admin_zone_list');
    return _list(value);
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final name = TextEditingController(text: row?['name']?.toString() ?? '');
    final city = TextEditingController(text: row?['city']?.toString() ?? 'Iquique');
    final country =
        TextEditingController(text: row?['country']?.toString() ?? 'Chile');
    final lat = TextEditingController(
      text: row?['center_latitude']?.toString() ?? '-20.2208',
    );
    final lng = TextEditingController(
      text: row?['center_longitude']?.toString() ?? '-70.1431',
    );
    final radius = TextEditingController(
      text: row?['radius_km']?.toString() ?? '25',
    );
    var active = row?['active'] != false;

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(row == null ? 'Nueva zona' : 'Editar zona'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: city,
                    decoration: const InputDecoration(labelText: 'Ciudad'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: country,
                    decoration: const InputDecoration(labelText: 'País'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: lat,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration:
                              const InputDecoration(labelText: 'Latitud'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: lng,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration:
                              const InputDecoration(labelText: 'Longitud'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: radius,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Radio de cobertura km'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    onChanged: (value) => setLocal(() => active = value),
                    title: const Text('Zona activa'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      try {
        await supabase.rpc(
          'admin_upsert_zone',
          params: {
            'p_id': row?['id'],
            'p_name': name.text.trim(),
            'p_city': city.text.trim(),
            'p_country': country.text.trim(),
            'p_active': active,
            'p_center_latitude': _num(lat.text),
            'p_center_longitude': _num(lng.text),
            'p_radius_km': _num(radius.text) ?? 25,
          },
        );
        if (mounted) setState(() => revision++);
      } catch (e) {
        if (mounted) _snack(context, e);
      }
    }

    name.dispose();
    city.dispose();
    country.dispose();
    lat.dispose();
    lng.dispose();
    radius.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(revision),
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading(title: 'Cargando zonas');
        }
        if (snapshot.hasError) {
          return _Error(error: snapshot.error, onRetry: () => setState(() => revision++));
        }

        final rows = snapshot.data ?? const [];
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            _Header(
              title: 'Zonas de operación',
              subtitle:
                  'Cobertura geográfica y radio de operación de Express.',
              action: FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nueva zona'),
              ),
            ),
            const SizedBox(height: 18),
            if (rows.isEmpty)
              const _Empty(text: 'No hay zonas configuradas.')
            else
              ...rows.map(
                (row) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFEAF2FF),
                      child: Icon(
                        row['active'] == true
                            ? Icons.location_on_rounded
                            : Icons.location_off_outlined,
                        color: _blue,
                      ),
                    ),
                    title: Text(
                      row['name']?.toString() ?? 'Zona',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      (row['city'] ?? '—').toString() +
                          ' · ' +
                          (row['country'] ?? '—').toString() +
                          ' · radio ' +
                          (row['radius_km'] ?? '—').toString() +
                          ' km',
                    ),
                    trailing: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          label: Text(
                            row['active'] == true ? 'Activa' : 'Inactiva',
                          ),
                        ),
                        IconButton(
                          onPressed: () => _edit(row),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class AdminFaresPage extends StatefulWidget {
  const AdminFaresPage({super.key});

  @override
  State<AdminFaresPage> createState() => _AdminFaresPageState();
}

class _AdminFaresPageState extends State<AdminFaresPage> {
  int revision = 0;

  Future<({List<Map<String, dynamic>> fares, List<Map<String, dynamic>> zones})>
      _load() async {
    final values = await Future.wait([
      supabase.rpc('admin_fare_list'),
      supabase.rpc('admin_zone_list'),
    ]);
    return (fares: _list(values[0]), zones: _list(values[1]));
  }

  Future<void> _edit(
    List<Map<String, dynamic>> zones, [
    Map<String, dynamic>? row,
  ]) async {
    var scope = row?['scope_type']?.toString() ?? 'global';
    var service = row?['service_key']?.toString() ?? 'ride';
    String? zoneId = row?['zone_id']?.toString();
    var active = row?['active'] != false;

    final base = TextEditingController(
      text: row?['base_fare']?.toString() ?? '5',
    );
    final km = TextEditingController(
      text: row?['per_km']?.toString() ?? '1',
    );
    final minute = TextEditingController(
      text: row?['per_minute']?.toString() ?? '0',
    );
    final minimum = TextEditingController(
      text: row?['minimum_fare']?.toString() ?? '5',
    );
    final surge = TextEditingController(
      text: row?['surge_multiplier']?.toString() ?? '1',
    );
    final commission = TextEditingController(
      text: row?['commission_percent']?.toString() ?? '0',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(row == null ? 'Nueva tarifa' : 'Editar tarifa'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: scope,
                    decoration: const InputDecoration(labelText: 'Jerarquía'),
                    items: const [
                      DropdownMenuItem(
                        value: 'global',
                        child: Text('Global'),
                      ),
                      DropdownMenuItem(
                        value: 'service',
                        child: Text('Por servicio'),
                      ),
                      DropdownMenuItem(
                        value: 'zone_service',
                        child: Text('Zona + servicio'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setLocal(() => scope = value);
                    },
                  ),
                  if (scope != 'global') ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: service,
                      decoration:
                          const InputDecoration(labelText: 'Servicio'),
                      items: const [
                        DropdownMenuItem(value: 'ride', child: Text('Viaje')),
                        DropdownMenuItem(
                          value: 'delivery',
                          child: Text('Delivery'),
                        ),
                        DropdownMenuItem(
                          value: 'economy',
                          child: Text('Express / Economy'),
                        ),
                        DropdownMenuItem(
                          value: 'comfort',
                          child: Text('Comfort'),
                        ),
                        DropdownMenuItem(value: 'xl', child: Text('XL')),
                        DropdownMenuItem(
                          value: 'motorcycle',
                          child: Text('Moto'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setLocal(() => service = value);
                      },
                    ),
                  ],
                  if (scope == 'zone_service') ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: zoneId,
                      decoration: const InputDecoration(labelText: 'Zona'),
                      items: zones
                          .map(
                            (zone) => DropdownMenuItem(
                              value: zone['id'].toString(),
                              child: Text(zone['name']?.toString() ?? 'Zona'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocal(() => zoneId = value),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _NumberField(controller: base, label: 'Tarifa base'),
                  const SizedBox(height: 10),
                  _NumberField(controller: km, label: 'Precio por km'),
                  const SizedBox(height: 10),
                  _NumberField(controller: minute, label: 'Precio por minuto'),
                  const SizedBox(height: 10),
                  _NumberField(controller: minimum, label: 'Tarifa mínima'),
                  const SizedBox(height: 10),
                  _NumberField(
                    controller: surge,
                    label: 'Multiplicador dinámico',
                  ),
                  const SizedBox(height: 10),
                  _NumberField(
                    controller: commission,
                    label: 'Comisión %',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    onChanged: (value) => setLocal(() => active = value),
                    title: const Text('Regla activa'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      try {
        await supabase.rpc(
          'admin_upsert_fare_rule',
          params: {
            'p_id': row?['id'],
            'p_scope_type': scope,
            'p_service_key': scope == 'global' ? null : service,
            'p_zone_id': scope == 'zone_service' ? zoneId : null,
            'p_base_fare': _num(base.text) ?? 0,
            'p_per_km': _num(km.text) ?? 0,
            'p_per_minute': _num(minute.text) ?? 0,
            'p_minimum_fare': _num(minimum.text) ?? 0,
            'p_surge_multiplier': _num(surge.text) ?? 1,
            'p_commission_percent': _num(commission.text) ?? 0,
            'p_active': active,
          },
        );
        if (mounted) setState(() => revision++);
      } catch (e) {
        if (mounted) _snack(context, e);
      }
    }

    base.dispose();
    km.dispose();
    minute.dispose();
    minimum.dispose();
    surge.dispose();
    commission.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
        ({List<Map<String, dynamic>> fares, List<Map<String, dynamic>> zones})>(
      key: ValueKey(revision),
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading(title: 'Cargando tarifas');
        }
        if (snapshot.hasError) {
          return _Error(error: snapshot.error, onRetry: () => setState(() => revision++));
        }

        final data = snapshot.data ??
            (fares: <Map<String, dynamic>>[], zones: <Map<String, dynamic>>[]);
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            _Header(
              title: 'Motor de tarifas',
              subtitle:
                  'Jerarquía Global → Servicio → Zona + Servicio.',
              action: FilledButton.icon(
                onPressed: () => _edit(data.zones),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nueva regla'),
              ),
            ),
            const SizedBox(height: 18),
            ...data.fares.map(
              (row) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEAF2FF),
                    child: Icon(Icons.payments_outlined, color: _blue),
                  ),
                  title: Text(
                    _fareTitle(row),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    'Base ' +
                        (row['base_fare'] ?? 0).toString() +
                        ' · km ' +
                        (row['per_km'] ?? 0).toString() +
                        ' · min ' +
                        (row['per_minute'] ?? 0).toString() +
                        ' · mínimo ' +
                        (row['minimum_fare'] ?? 0).toString() +
                        ' · comisión ' +
                        (row['commission_percent'] ?? 0).toString() +
                        '%',
                  ),
                  trailing: IconButton(
                    onPressed: () => _edit(data.zones, row),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class AdminPaymentsPage extends StatefulWidget {
  const AdminPaymentsPage({super.key});

  @override
  State<AdminPaymentsPage> createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends State<AdminPaymentsPage> {
  int revision = 0;

  Future<Map<String, dynamic>> _load() async {
    final value = await supabase.rpc('admin_payment_overview');
    return _map(value);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(revision),
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading(title: 'Cargando pagos');
        }
        if (snapshot.hasError) {
          return _Error(error: snapshot.error, onRetry: () => setState(() => revision++));
        }

        final data = snapshot.data ?? const {};
        final summary = _map(data['summary']);
        final recent = _list(data['recent']);

        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const _Header(
              title: 'Pagos y Billetera',
              subtitle:
                  'Cobros, pendientes, saldos y movimientos recientes.',
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Kpi('Cobrado hoy', 'Bs ' + (summary['paid_today'] ?? 0).toString()),
                _Kpi(
                  'Pendiente',
                  'Bs ' + (summary['pending_total'] ?? 0).toString(),
                ),
                _Kpi(
                  'Pagos hoy',
                  (summary['paid_count_today'] ?? 0).toString(),
                ),
                _Kpi(
                  'Saldo wallet',
                  'Bs ' +
                      (summary['wallet_balance_total'] ?? 0).toString(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Movimientos recientes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (recent.isEmpty)
              const _Empty(text: 'No hay movimientos.')
            else
              ...recent.map(
                (row) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      row['method'] == 'wallet'
                          ? Icons.account_balance_wallet_rounded
                          : row['method'] == 'cash'
                              ? Icons.payments_outlined
                              : Icons.credit_card_rounded,
                      color: _blue,
                    ),
                    title: Text(
                      (row['currency'] ?? 'BOB').toString() +
                          ' ' +
                          (row['amount'] ?? 0).toString(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      (row['method'] ?? '—').toString() +
                          ' · ' +
                          (row['status'] ?? '—').toString() +
                          ' · ' +
                          _formatDate(row['created_at']),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  DateTime from = DateTime.now().subtract(const Duration(days: 30));
  DateTime to = DateTime.now().add(const Duration(days: 1));
  int revision = 0;

  Future<Map<String, dynamic>> _load() async {
    final value = await supabase.rpc(
      'admin_report_summary',
      params: {
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      },
    );
    return _map(value);
  }

  Future<void> _pickFrom() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDate: from,
    );
    if (selected != null) {
      setState(() {
        from = selected;
        revision++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(revision),
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading(title: 'Generando reporte');
        }
        if (snapshot.hasError) {
          return _Error(error: snapshot.error, onRetry: () => setState(() => revision++));
        }

        final data = snapshot.data ?? const {};
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            _Header(
              title: 'Reportes',
              subtitle:
                  'Resumen operativo y financiero del período seleccionado.',
              action: OutlinedButton.icon(
                onPressed: _pickFrom,
                icon: const Icon(Icons.date_range_outlined),
                label: Text('Desde ' + _dateOnly(from)),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Kpi('Viajes', (data['trips_total'] ?? 0).toString()),
                _Kpi(
                  'Viajes completados',
                  (data['trips_completed'] ?? 0).toString(),
                ),
                _Kpi(
                  'Viajes cancelados',
                  (data['trips_cancelled'] ?? 0).toString(),
                ),
                _Kpi('Delivery', (data['delivery_total'] ?? 0).toString()),
                _Kpi(
                  'Delivery completados',
                  (data['delivery_completed'] ?? 0).toString(),
                ),
                _Kpi(
                  'Cobrado',
                  'Bs ' + (data['paid_volume'] ?? 0).toString(),
                ),
                _Kpi('Usuarios nuevos', (data['new_users'] ?? 0).toString()),
                _Kpi('Emergencias', (data['emergencies'] ?? 0).toString()),
              ],
            ),
          ],
        );
      },
    );
  }
}

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  Map<String, dynamic>? settings;
  bool loading = true;
  bool saving = false;

  late final TextEditingController currency;
  late final TextEditingController rideMin;
  late final TextEditingController deliveryMin;
  late final TextEditingController commission;
  late final TextEditingController radius;
  late final TextEditingController dispatchRadius;
  late final TextEditingController timeout;
  late final TextEditingController radiusStep;
  late final TextEditingController timezone;
  late final TextEditingController country;
  late final TextEditingController supportPhone;
  late final TextEditingController supportWhatsapp;

  bool cash = true;
  bool card = false;
  bool wallet = false;
  bool rideEnabled = true;
  bool deliveryEnabled = true;
  String dispatchMode = 'broadcast';

  @override
  void initState() {
    super.initState();
    currency = TextEditingController();
    rideMin = TextEditingController();
    deliveryMin = TextEditingController();
    commission = TextEditingController();
    radius = TextEditingController();
    dispatchRadius = TextEditingController();
    timeout = TextEditingController();
    radiusStep = TextEditingController();
    timezone = TextEditingController();
    country = TextEditingController();
    supportPhone = TextEditingController();
    supportWhatsapp = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await supabase.rpc('admin_settings_get');
      final row = _map(value);
      settings = row;
      currency.text = (row['currency'] ?? 'BOB').toString();
      rideMin.text = (row['min_ride_fare'] ?? 5).toString();
      deliveryMin.text = (row['min_delivery_fare'] ?? 5).toString();
      commission.text = (row['commission_percent'] ?? 0).toString();
      radius.text = (row['service_radius_km'] ?? 30).toString();
      dispatchRadius.text = (row['dispatch_radius_km'] ?? 5).toString();
      timeout.text = (row['offer_timeout_seconds'] ?? 45).toString();
      radiusStep.text =
          (row['progressive_radius_step_km'] ?? 2).toString();
      timezone.text =
          (row['timezone'] ?? 'America/Santiago').toString();
      country.text = (row['default_country'] ?? 'Chile').toString();
      supportPhone.text = row['support_phone']?.toString() ?? '';
      supportWhatsapp.text = row['support_whatsapp']?.toString() ?? '';
      cash = row['allow_cash'] != false;
      card = row['allow_card'] == true;
      wallet = row['allow_wallet'] == true;
      rideEnabled = row['ride_enabled'] != false;
      deliveryEnabled = row['delivery_enabled'] != false;
      dispatchMode = (row['dispatch_mode'] ?? 'broadcast').toString();
    } catch (e) {
      if (mounted) _snack(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final value = await supabase.rpc(
        'admin_settings_update',
        params: {
          'p_currency': currency.text.trim(),
          'p_min_ride_fare': _num(rideMin.text) ?? 0,
          'p_min_delivery_fare': _num(deliveryMin.text) ?? 0,
          'p_commission_percent': _num(commission.text) ?? 0,
          'p_service_radius_km': _num(radius.text) ?? 30,
          'p_allow_cash': cash,
          'p_allow_card': card,
          'p_allow_wallet': wallet,
          'p_ride_enabled': rideEnabled,
          'p_delivery_enabled': deliveryEnabled,
          'p_dispatch_mode': dispatchMode,
          'p_dispatch_radius_km': _num(dispatchRadius.text) ?? 5,
          'p_offer_timeout_seconds': int.tryParse(timeout.text) ?? 45,
          'p_progressive_radius_step_km': _num(radiusStep.text) ?? 2,
          'p_timezone': timezone.text.trim(),
          'p_default_country': country.text.trim(),
          'p_support_phone': supportPhone.text.trim(),
          'p_support_whatsapp': supportWhatsapp.text.trim(),
        },
      );
      settings = _map(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada.')),
        );
      }
    } catch (e) {
      if (mounted) _snack(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      currency,
      rideMin,
      deliveryMin,
      commission,
      radius,
      dispatchRadius,
      timeout,
      radiusStep,
      timezone,
      country,
      supportPhone,
      supportWhatsapp,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _Loading(title: 'Cargando configuración');

    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _Header(
          title: 'Configuración general',
          subtitle:
              'Módulos, pagos, dispatch y parámetros globales de Express.',
          action: FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar cambios'),
          ),
        ),
        const SizedBox(height: 18),
        _SettingsCard(
          title: 'Servicios',
          children: [
            SwitchListTile(
              value: rideEnabled,
              onChanged: (value) => setState(() => rideEnabled = value),
              title: const Text('Viajes habilitados'),
            ),
            SwitchListTile(
              value: deliveryEnabled,
              onChanged: (value) => setState(() => deliveryEnabled = value),
              title: const Text('Delivery habilitado'),
            ),
          ],
        ),
        _SettingsCard(
          title: 'Métodos de pago',
          children: [
            SwitchListTile(
              value: cash,
              onChanged: (value) => setState(() => cash = value),
              title: const Text('Efectivo'),
            ),
            SwitchListTile(
              value: card,
              onChanged: (value) => setState(() => card = value),
              title: const Text('Tarjeta'),
            ),
            SwitchListTile(
              value: wallet,
              onChanged: (value) => setState(() => wallet = value),
              title: const Text('Billetera Express'),
            ),
          ],
        ),
        _SettingsCard(
          title: 'Operación y dispatch',
          children: [
            DropdownButtonFormField<String>(
              initialValue: dispatchMode,
              decoration: const InputDecoration(labelText: 'Modo de dispatch'),
              items: const [
                DropdownMenuItem(
                  value: 'broadcast',
                  child: Text('Broadcast'),
                ),
                DropdownMenuItem(
                  value: 'progressive',
                  child: Text('Progresivo'),
                ),
                DropdownMenuItem(
                  value: 'manual',
                  child: Text('Manual'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => dispatchMode = value);
              },
            ),
            const SizedBox(height: 10),
            _NumberField(
              controller: dispatchRadius,
              label: 'Radio inicial de dispatch km',
            ),
            const SizedBox(height: 10),
            _NumberField(
              controller: radiusStep,
              label: 'Aumento de radio progresivo km',
            ),
            const SizedBox(height: 10),
            _NumberField(
              controller: timeout,
              label: 'Timeout de oferta segundos',
            ),
          ],
        ),
        _SettingsCard(
          title: 'Tarifas globales y alcance',
          children: [
            _NumberField(controller: rideMin, label: 'Mínimo Viaje'),
            const SizedBox(height: 10),
            _NumberField(controller: deliveryMin, label: 'Mínimo Delivery'),
            const SizedBox(height: 10),
            _NumberField(controller: commission, label: 'Comisión global %'),
            const SizedBox(height: 10),
            _NumberField(controller: radius, label: 'Radio máximo km'),
            const SizedBox(height: 10),
            TextField(
              controller: currency,
              decoration: const InputDecoration(labelText: 'Moneda'),
            ),
          ],
        ),
        _SettingsCard(
          title: 'Localización y soporte',
          children: [
            TextField(
              controller: timezone,
              decoration: const InputDecoration(labelText: 'Zona horaria'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: country,
              decoration: const InputDecoration(labelText: 'País'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: supportPhone,
              decoration:
                  const InputDecoration(labelText: 'Teléfono de soporte'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: supportWhatsapp,
              decoration:
                  const InputDecoration(labelText: 'WhatsApp de soporte'),
            ),
          ],
        ),
      ],
    );
  }
}

class AdminBuildsPage extends StatefulWidget {
  const AdminBuildsPage({super.key});

  @override
  State<AdminBuildsPage> createState() => _AdminBuildsPageState();
}

class _AdminBuildsPageState extends State<AdminBuildsPage> {
  int revision = 0;

  Future<List<Map<String, dynamic>>> _load() async {
    final value = await supabase.rpc('admin_build_list');
    return _list(value);
  }

  Future<void> _create() async {
    final version = TextEditingController(text: '1.4.0');
    final build = TextEditingController(text: '33');
    final changelog = TextEditingController();
    String artifact = 'apk';

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Preparar build Android'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: artifact,
                  decoration: const InputDecoration(labelText: 'Artifact'),
                  items: const [
                    DropdownMenuItem(value: 'apk', child: Text('APK')),
                    DropdownMenuItem(value: 'aab', child: Text('AAB')),
                  ],
                  onChanged: (value) {
                    if (value != null) setLocal(() => artifact = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: version,
                  decoration: const InputDecoration(labelText: 'Versión'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: build,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Build number'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: changelog,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Notas del build'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Crear solicitud'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      try {
        await supabase.rpc(
          'admin_create_build_job',
          params: {
            'p_platform': 'android',
            'p_artifact_type': artifact,
            'p_version_name': version.text.trim(),
            'p_build_number': int.tryParse(build.text) ?? 1,
            'p_changelog': changelog.text.trim(),
            'p_commit_sha': null,
          },
        );
        if (mounted) setState(() => revision++);
      } catch (e) {
        if (mounted) _snack(context, e);
      }
    }

    version.dispose();
    build.dispose();
    changelog.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(revision),
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Loading(title: 'Cargando builds');
        }
        if (snapshot.hasError) {
          return _Error(error: snapshot.error, onRetry: () => setState(() => revision++));
        }

        final rows = snapshot.data ?? const [];
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            _Header(
              title: 'Build Center',
              subtitle:
                  'Registro y seguimiento de APK/AAB. La ejecución automática de GitHub Actions se conectará en el siguiente bloque seguro.',
              action: FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Preparar build'),
              ),
            ),
            const SizedBox(height: 14),
            const Card(
              color: Color(0xFFFFF7E8),
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Seguridad: todavía no se envía ningún token de GitHub al navegador. El disparo automático se hará mediante backend/Edge Function con secretos protegidos.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const _Empty(text: 'Todavía no hay builds registrados.')
            else
              ...rows.map(
                (row) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.android_rounded, color: _blue),
                    title: Text(
                      (row['artifact_type'] ?? '').toString().toUpperCase() +
                          ' · v' +
                          (row['version_name'] ?? '—').toString() +
                          ' (' +
                          (row['build_number'] ?? '—').toString() +
                          ')',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      (row['status'] ?? 'queued').toString() +
                          ' · ' +
                          _formatDate(row['created_at']),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;

  const _Header({
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, height: 1.35),
              ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 12),
          action!,
        ],
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String title;
  final String value;

  const _Kpi(this.title, this.value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(title, style: const TextStyle(color: _muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _NumberField({
    required this.controller,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(text, style: const TextStyle(color: _muted)),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  final String title;
  const _Loading({required this.title});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 18),
        const LinearProgressIndicator(),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _Error({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 46),
              const SizedBox(height: 10),
              Text(error.toString()),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

num? _num(String value) {
  return num.tryParse(value.trim().replaceAll(',', '.'));
}

void _snack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Error: ' + error.toString())),
  );
}

String _fareTitle(Map<String, dynamic> row) {
  final scope = row['scope_type']?.toString();
  if (scope == 'global') return 'Global';
  if (scope == 'service') {
    return 'Servicio · ' + (row['service_key'] ?? '—').toString();
  }
  return (row['zone_name'] ?? 'Zona').toString() +
      ' · ' +
      (row['service_key'] ?? '—').toString();
}

String _formatDate(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (date == null) return '—';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return day +
      '/' +
      month +
      '/' +
      date.year.toString() +
      ' · ' +
      hour +
      ':' +
      minute;
}

String _dateOnly(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return day + '/' + month + '/' + value.year.toString();
}

import 'package:flutter/material.dart';

import 'benefits_service.dart';
import 'core/runtime_channel.dart';
import 'money_format.dart';

class BenefitsPage extends StatefulWidget {
  const BenefitsPage({super.key, this.driver = false});
  final bool driver;

  @override
  State<BenefitsPage> createState() => _BenefitsPageState();
}

class _BenefitsPageState extends State<BenefitsPage> {
  final _service = BenefitsService();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.overview();
  }

  void _refresh() => setState(() => _future = _service.overview());

  String _label(String type) => switch (type) {
        'coupon' => 'Cupones',
        'activation' => 'Bienvenida y recompensas',
        'loyalty' => 'Fidelidad',
        'referral' => 'Invita y gana',
        _ => 'Beneficio Express',
      };

  IconData _icon(String type) => switch (type) {
        'coupon' => Icons.local_offer_outlined,
        'activation' => Icons.card_giftcard_outlined,
        'loyalty' => Icons.stars_outlined,
        'referral' => Icons.people_alt_outlined,
        _ => Icons.redeem_outlined,
      };

  Widget _card(BuildContext context, Map<String, dynamic> item) {
    final config = item['config'] is Map
        ? Map<String, dynamic>.from(item['config'] as Map)
        : <String, dynamic>{};
    final description = item['description']?.toString().trim() ?? '';
    final code = config['code']?.toString();
    final amount = config['value'];
    final kind = config['discount_type']?.toString();
    final detail = amount == null
        ? description
        : '${kind == 'percent' ? '$amount% de descuento' : expressMoney(amount, item['currency']?.toString())}'
            '${description.isEmpty ? '' : ' · $description'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFEAF2FF),
            foregroundColor: const Color(0xFF1769E0),
            child: Icon(_icon(item['type']?.toString() ?? '')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_label(item['type']?.toString() ?? ''),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 4),
              Text(item['name']?.toString() ?? 'Beneficio Express',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(color: Color(0xFF667085))),
              ],
              if (code != null && code.isNotEmpty) ...[
                const SizedBox(height: 9),
                SelectableText('Código: $code',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ]),
          ),
          const Icon(Icons.verified_outlined, color: Color(0xFF16A36A)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.driver ? 'Conductor' : 'Pasajero';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beneficios Express', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 12),
                const Text('No se pudieron cargar tus beneficios.'),
                TextButton(onPressed: _refresh, child: const Text('Reintentar')),
              ]),
            ));
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final items = data['items'] is List
              ? (data['items'] as List).whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row)).toList()
              : <Map<String, dynamic>>[];
          final history = data['history'] is List
              ? (data['history'] as List).whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row)).toList()
              : <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(padding: const EdgeInsets.all(18), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF073B8C), Color(0xFF1769E0)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Hola, $role', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('Aquí aparecen las promociones disponibles para tu cuenta y zona.',
                      style: TextStyle(color: Color(0xFFDCEAFF))),
                ]),
              ),
              const SizedBox(height: 18),
              Text(widget.driver ? 'Programas para conductores' : 'Para ti',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              if (widget.driver)
                const Card(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Los retos y referidos de conductores aparecerán aquí cuando el programa esté configurado. Los premios se mostrarán según sus reglas aprobadas.'),
                )),
              if (items.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Todavía no hay beneficios activos en tu zona.'),
                ))
              else
                ...items.map((item) => _card(context, item)),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Historial de beneficios',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                ...history.map((item) => ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(item['benefit_type']?.toString() ?? 'Beneficio'),
                      subtitle: Text(item['state']?.toString() ?? 'Pendiente'),
                      trailing: Text(expressMoney(item['amount'], data['currency']?.toString() ?? 'BOB')),
                    )),
              ],
              const SizedBox(height: 12),
              Text('Entorno ${ExpressRuntimeChannel.name == 'preview' ? 'de prueba' : 'de producción'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 11)),
            ]),
          );
        },
      ),
    );
  }
}

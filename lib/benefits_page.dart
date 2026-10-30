import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late Future<Map<String, dynamic>> _referralFuture;
  final _referralCode = TextEditingController();
  bool _referralSaving = false;

  @override
  void initState() {
    super.initState();
    _future = _service.overview();
    _referralFuture = widget.driver
        ? _service.driverReferralStatus()
        : Future<Map<String, dynamic>>.value(const <String, dynamic>{});
  }

  @override
  void dispose() {
    _referralCode.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {
        _future = _service.overview();
        if (widget.driver) _referralFuture = _service.driverReferralStatus();
      });

  Future<void> _applyReferral() async {
    if (_referralSaving || _referralCode.text.trim().isEmpty) return;
    setState(() => _referralSaving = true);
    try {
      await _service.applyDriverReferralCode(_referralCode.text);
      _referralCode.clear();
      if (!mounted) return;
      setState(() => _referralFuture = _service.driverReferralStatus());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Código de referido registrado. Los bonos se generan cuando pague un plan.'),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo registrar el código. Verifica que sea válido y que el programa esté activo en Bolivia.'),
      ));
    } finally {
      if (mounted) setState(() => _referralSaving = false);
    }
  }

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
                FutureBuilder<Map<String, dynamic>>(
                  future: _referralFuture,
                  builder: (context, referralSnapshot) {
                    final referral = referralSnapshot.data ?? const <String, dynamic>{};
                    final code = referral['code']?.toString() ?? '';
                    return Card(child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Invita a otro conductor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        const Text('Recibe el porcentaje configurado de cada pago de plan confirmado en Bolivia. El crédito va a tu billetera interna.'),
                        if (referral['eligible'] == false)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('Este programa de referidos está disponible para conductores con zona en Bolivia.'),
                          ),
                        if (code.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: SelectableText('Tu código: $code', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
                            IconButton(tooltip: 'Copiar código', onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: code));
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado.')));
                            }, icon: const Icon(Icons.copy_rounded)),
                          ]),
                          Text('${referral['referrals'] ?? 0} conductores referidos · ${expressMoney(referral['credited_total'], 'BOB')} acreditados', style: const TextStyle(color: Color(0xFF667085))),
                        ],
                        if (referral['eligible'] != false && referral['has_referrer'] == true)
                          const Padding(padding: EdgeInsets.only(top: 12), child: Text('Ya tienes un conductor invitador registrado.'))
                        else if (referral['eligible'] != false) ...[
                          const SizedBox(height: 14),
                          TextField(controller: _referralCode, textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(labelText: 'Código del conductor que te invitó')),
                          const SizedBox(height: 9),
                          SizedBox(width: double.infinity, child: FilledButton(
                            onPressed: _referralSaving ? null : _applyReferral,
                            child: Text(_referralSaving ? 'Registrando…' : 'Registrar invitador'),
                          )),
                        ],
                        if (referralSnapshot.hasError)
                          const Text('Los referidos están disponibles para conductores aprobados con zona en Bolivia.', style: TextStyle(color: Color(0xFF667085))),
                      ]),
                    ));
                  },
                ),
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

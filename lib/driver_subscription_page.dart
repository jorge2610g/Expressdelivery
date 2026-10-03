import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/supabase_client.dart';

int _subscriptionInt(Object? raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

String _subscriptionPriceLabel(Object? amount, Object? currency) {
  final value = amount is num
      ? amount.toDouble()
      : double.tryParse(amount?.toString() ?? '') ?? 0;
  final code = (currency?.toString() ?? 'CLP').toUpperCase();
  final integer = value.round().toString();
  final grouped = integer.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  if (code == 'CLP') return 'CLP ' + grouped;
  if (code == 'BOB') return 'Bs ' + grouped;
  return code + ' ' + grouped;
}

class DriverSubscriptionPage extends StatefulWidget {
  const DriverSubscriptionPage({super.key});

  @override
  State<DriverSubscriptionPage> createState() => _DriverSubscriptionPageState();
}

class _DriverSubscriptionPageState extends State<DriverSubscriptionPage>
    with WidgetsBindingObserver {
  bool loading = true;
  bool refreshing = false;
  String? error;
  Map<String, dynamic> state = const {};
  List<Map<String, dynamic>> plans = const [];
  List<Map<String, dynamic>> payments = const [];
  Timer? countdownTimer;
  RealtimeChannel? subscriptionChannel;
  RealtimeChannel? paymentChannel;

  String get userId => supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && state['expires_at'] != null) setState(() {});
    });
    _startRealtime();
  }

  void _startRealtime() {
    if (userId.isEmpty) return;
    subscriptionChannel = supabase
        .channel('driver-subscription-' + userId)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_subscriptions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: userId,
          ),
          callback: (_) => unawaited(_load(silent: true)),
        )
        .subscribe();

    paymentChannel = supabase
        .channel('driver-subscription-payments-' + userId)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_subscription_payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: userId,
          ),
          callback: (_) => unawaited(_load(silent: true)),
        )
        .subscribe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      unawaited(_load(silent: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    countdownTimer?.cancel();
    final sub = subscriptionChannel;
    final pay = paymentChannel;
    if (sub != null) unawaited(supabase.removeChannel(sub));
    if (pay != null) unawaited(supabase.removeChannel(pay));
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final response = await supabase.functions.invoke(
        'driver-subscription-payments',
        body: const {'action': 'state'},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (data['ok'] != true) {
        throw StateError(
          data['error']?.toString() ?? 'No se pudo cargar la suscripción',
        );
      }

      final history = await supabase
          .from('driver_subscription_payments')
          .select(
            'id,plan_id,amount,currency_code,provider,status,created_at,paid_at,expires_at,provider_order_id,qr_payload',
          )
          .order('created_at', ascending: false)
          .limit(30);

      final rawState = data['state'] is Map
          ? Map<String, dynamic>.from(data['state'] as Map)
          : <String, dynamic>{};
      final rawZone = data['zone'] is Map
          ? Map<String, dynamic>.from(data['zone'] as Map)
          : <String, dynamic>{};
      final rawPlans = _maps(data['plans']);
      final mergedState = <String, dynamic>{
        ...rawState,
        'feature_enabled':
            data['feature_enabled'] ?? rawState['feature_enabled'],
        'enforce_access':
            data['enforce_access'] ?? rawState['enforce_access'],
        'zone_name': rawZone['name'] ?? rawState['zone_name'],
        'zone_key': rawZone['zone_key'] ?? rawState['zone_key'],
        'currency_code': rawZone['currency_code'] ??
            rawState['currency_code'] ??
            (rawPlans.isNotEmpty ? rawPlans.first['currency_code'] : null),
        'payment_provider_key':
            data['payment_provider_key'] ?? rawState['payment_provider_key'],
        'payment_provider_label':
            data['payment_provider_label'] ??
                rawState['payment_provider_label'],
        'provider_enabled':
            data['provider_enabled'] ?? rawState['provider_enabled'],
        'provider_configured':
            data['provider_configured'] ?? rawState['provider_configured'],
      };

      if (!mounted) return;
      setState(() {
        state = mergedState;
        plans = rawPlans;
        payments = _maps(history);
        loading = false;
        refreshing = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        refreshing = false;
        error = e.toString();
      });
    }
  }

  Future<void> _refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    await _load(silent: true);
  }

  Duration _remaining() {
    final expires = DateTime.tryParse(state['expires_at']?.toString() ?? '');
    if (expires == null) return Duration.zero;
    final left = expires.toUtc().difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _date(Object? raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (value == null) return '—';
    return _two(value.day) +
        '/' +
        _two(value.month) +
        '/' +
        value.year.toString() +
        ' · ' +
        _two(value.hour) +
        ':' +
        _two(value.minute);
  }

  String _groupThousands(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  String _money(Object? amount, [String? currency]) {
    final value = amount is num
        ? amount.toDouble()
        : double.tryParse(amount?.toString() ?? '') ?? 0;
    final code = (currency ??
            state['currency_code']?.toString() ??
            'BOB')
        .trim()
        .toUpperCase();
    final isInteger = value == value.roundToDouble();
    final raw = isInteger
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    final parts = raw.split('.');
    final integerPart = _groupThousands(parts.first);
    final shown = parts.length == 1
        ? integerPart
        : integerPart + ',' + parts.last;

    switch (code) {
      case 'BOB':
        return 'Bs ' + shown;
      case 'CLP':
        return 'CLP ' + integerPart;
      case 'USD':
        return 'USD ' + shown;
      default:
        return code + ' ' + shown;
    }
  }

  String _paymentProviderLabel() {
    final explicit = state['payment_provider_label']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final key = state['payment_provider_key']?.toString();
    switch (key) {
      case 'mercado_pago':
        return 'Mercado Pago';
      case 'veripagos_qr':
        return 'QR Bolivia';
      default:
        return 'método de pago';
    }
  }

  List<String> _benefits(Map<String, dynamic> plan) {
    final raw = plan['benefits'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  Future<void> _resumePendingPayment(
    Map<String, dynamic> payment,
  ) async {
    final status = payment['status']?.toString() ?? '';
    if (status != 'pending' && status != 'in_process') return;

    Map<String, dynamic> data = <String, dynamic>{
      ...payment,
      'payment_id': payment['id'],
      'checkout_url': payment['qr_payload'],
      'qr': payment['qr_payload'],
    };

    try {
      final provider = payment['provider']?.toString() ?? '';
      final payload = payment['qr_payload']?.toString() ?? '';
      if (payload.trim().isEmpty) {
        final planId = payment['plan_id'];
        final response = await supabase.functions.invoke(
          'driver-subscription-payments',
          body: {'action': 'create', 'plan_id': planId},
        );
        final refreshed = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};
        if (refreshed['ok'] != true) {
          throw StateError(
            refreshed['error']?.toString() ??
                'No se pudo recuperar el pago pendiente',
          );
        }
        data = <String, dynamic>{...data, ...refreshed};
      } else if (provider == 'mercado_pago') {
        data['provider'] = 'mercado_pago';
        data['checkout_url'] = payload;
      } else {
        data['provider'] = provider;
        data['qr'] = payload;
      }

      if (!mounted) return;
      if (data['provider']?.toString() == 'mercado_pago') {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _DriverSubscriptionMercadoPagoDialog(
            payment: data,
            onApproved: () => _load(silent: true),
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _DriverSubscriptionQrDialog(
            payment: data,
            onApproved: () => _load(silent: true),
          ),
        );
      }
      if (mounted) await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      _snack(
        'No se pudo reabrir el pago pendiente: ' +
            e.toString().replaceFirst('Bad state: ', ''),
      );
    }
  }

  Future<void> _buy(Map<String, dynamic> plan) async {
    if (state['feature_enabled'] != true) {
      final zone = state['zone_name']?.toString().trim();
      _snack(
        zone == null || zone.isEmpty
            ? 'Las suscripciones no están habilitadas en esta zona.'
            : 'Las suscripciones no están habilitadas en $zone.',
      );
      return;
    }
    if (state['provider_enabled'] != true) {
      final label = _paymentProviderLabel();
      if (state['provider_configured'] == true) {
        _snack(
          label +
              ' está conectado, pero el cobro de suscripciones todavía no está habilitado.',
        );
      } else {
        _snack(label + ' todavía está en configuración.');
      }
      return;
    }
    try {
      _snack(
        state['payment_provider_key'] == 'mercado_pago'
            ? 'Preparando Mercado Pago…'
            : 'Generando QR de pago…',
      );
      final response = await supabase.functions.invoke(
        'driver-subscription-payments',
        body: {'action': 'create', 'plan_id': plan['id']},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (data['ok'] != true) {
        throw StateError(
          data['error']?.toString() ?? 'No se pudo generar el QR',
        );
      }
      if (!mounted) return;
      if (data['provider']?.toString() == 'mercado_pago') {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _DriverSubscriptionMercadoPagoDialog(
            payment: data,
            onApproved: () => _load(silent: true),
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _DriverSubscriptionQrDialog(
            payment: data,
            onApproved: () => _load(silent: true),
          ),
        );
      }
      if (mounted) await _load(silent: true);
    } catch (e) {
      if (mounted) _snack(e.toString());
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF0F1012) : const Color(0xFFF5F7FB);
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Suscripción')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Suscripción'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: refreshing ? null : _refresh,
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            if (error != null)
              _Notice(
                icon: Icons.error_outline_rounded,
                title: 'No se pudo actualizar',
                body: error!,
              ),
            if (state['feature_enabled'] != true)
              const _Notice(
                icon: Icons.info_outline_rounded,
                title: 'Suscripciones en preparación',
                body: 'Tu operación actual continúa sin cambios.',
              ),
            _CurrentSubscriptionCard(
              state: state,
              remaining: _remaining(),
              formatDate: _date,
            ),
            const SizedBox(height: 18),
            const Text(
              'Elige tu plan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              state['feature_enabled'] != true
                  ? 'Las suscripciones están desactivadas en ${state['zone_name'] ?? 'esta zona'}. Puedes seguir operando según la configuración local.'
                  : state['provider_enabled'] == true
                      ? 'Paga con ' + _paymentProviderLabel() + '. La activación se confirma automáticamente.'
                      : state['provider_configured'] == true
                          ? _paymentProviderLabel() + ' está conectado y verificado. El checkout de suscripciones todavía no está habilitado.'
                          : _paymentProviderLabel() + ' todavía no está configurado para suscripciones en esta zona.',
              style: const TextStyle(
                color: Color(0xFF667085),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (state['feature_enabled'] == true)
              for (final plan in plans) ...[
                _PlanCard(
                  plan: plan,
                  price: _money(
                    plan['amount'],
                    plan['currency_code']?.toString(),
                  ),
                  benefits: _benefits(plan),
                  enabled: state['provider_enabled'] == true,
                  providerConfigured: state['provider_configured'] == true,
                  paymentLabel: _paymentProviderLabel(),
                  paymentProviderKey:
                      state['payment_provider_key']?.toString(),
                  onBuy: () => _buy(plan),
                ),
                const SizedBox(height: 10),
              ]
            else
              const _Notice(
                icon: Icons.visibility_off_outlined,
                title: 'Planes ocultos',
                body:
                    'Administración tiene las suscripciones desactivadas para esta zona.',
              ),
            const SizedBox(height: 10),
            const Text(
              'Historial de pagos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (payments.isEmpty)
              const _Notice(
                icon: Icons.receipt_long_outlined,
                title: 'Todavía no hay pagos',
                body: 'Tus pagos de suscripción aparecerán aquí.',
              )
            else
              for (final payment in payments)
                _PaymentRow(
                  payment: payment,
                  date: _date(payment['created_at']),
                  price: _money(
                    payment['amount'],
                    payment['currency_code']?.toString(),
                  ),
                  provider: payment['provider']?.toString(),
                  onTap: () => _resumePendingPayment(payment),
                ),
          ],
        ),
      ),
    );
  }
}

class _CurrentSubscriptionCard extends StatelessWidget {
  final Map<String, dynamic> state;
  final Duration remaining;
  final String Function(Object?) formatDate;

  const _CurrentSubscriptionCard({
    required this.state,
    required this.remaining,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final active = state['usable'] == true;
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    final plan = state['plan_name']?.toString();
    final status = state['status']?.toString() ?? 'inactive';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active
              ? const [Color(0xFF0B57D0), Color(0xFF073B8C)]
              : const [Color(0xFF202733), Color(0xFF111827)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            active ? 'SUSCRIPCIÓN ACTIVA' : 'SIN SUSCRIPCIÓN ACTIVA',
            style: const TextStyle(
              color: Color(0xFFFFC928),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .9,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            active ? (plan ?? 'Plan Express') : 'Elige un plan para comenzar',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (active) ...[
            const SizedBox(height: 6),
            Text(
              'Vence: ' + formatDate(state['expires_at']),
              style: const TextStyle(color: Color(0xFFD7E2F4)),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _CountUnit(
                  value: days.toString().padLeft(2, '0'),
                  label: 'Días',
                ),
                _CountUnit(
                  value: hours.toString().padLeft(2, '0'),
                  label: 'Horas',
                ),
                _CountUnit(
                  value: minutes.toString().padLeft(2, '0'),
                  label: 'Min',
                ),
                _CountUnit(
                  value: seconds.toString().padLeft(2, '0'),
                  label: 'Seg',
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              status == 'suspended'
                  ? 'Tu suscripción está suspendida.'
                  : 'Los viajes actuales no se bloquearán mientras el administrador mantenga el modo de exigencia desactivado.',
              style: const TextStyle(
                color: Color(0xFFD7E2F4),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountUnit extends StatelessWidget {
  final String value;
  final String label;
  const _CountUnit({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 7),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0x22FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x2EFFFFFF)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFCAD8ED),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final String price;
  final List<String> benefits;
  final bool enabled;
  final bool providerConfigured;
  final String paymentLabel;
  final String? paymentProviderKey;
  final VoidCallback onBuy;

  const _PlanCard({
    required this.plan,
    required this.price,
    required this.benefits,
    required this.enabled,
    required this.providerConfigured,
    required this.paymentLabel,
    required this.paymentProviderKey,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final days = _subscriptionInt(plan['days']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['name']?.toString() ?? 'Plan',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        days.toString() + (days == 1 ? ' día' : ' días'),
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                ),
                Text(
                  price,
                  style: const TextStyle(
                    color: Color(0xFF0B57D0),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (benefits.isNotEmpty) ...[
              const SizedBox(height: 13),
              for (final benefit in benefits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF12B76A),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(benefit)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enabled ? onBuy : null,
                icon: Icon(
                  paymentProviderKey == 'veripagos_qr'
                      ? Icons.qr_code_2_rounded
                      : Icons.account_balance_wallet_rounded,
                ),
                label: Text(
                  enabled
                      ? 'Pagar con ' + paymentLabel
                      : providerConfigured
                          ? paymentLabel + ' conectado'
                          : paymentLabel + ' en configuración',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Map<String, dynamic> payment;
  final String date;
  final String price;
  final String? provider;
  final VoidCallback onTap;

  const _PaymentRow({
    required this.payment,
    required this.date,
    required this.price,
    required this.provider,
    required this.onTap,
  });

  String get providerLabel {
    switch (provider) {
      case 'mercado_pago':
        return 'Mercado Pago';
      case 'veripagos':
      case 'veripagos_qr':
        return 'QR Bolivia';
      default:
        return provider == null || provider!.isEmpty ? 'Pago' : provider!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = payment['status']?.toString() ?? 'pending';
    final positive = status == 'approved';
    final canResume = status == 'pending' || status == 'in_process';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: canResume ? onTap : null,
        leading: CircleAvatar(
          backgroundColor: positive
              ? const Color(0xFFE7F8EF)
              : const Color(0xFFFFF3E0),
          child: Icon(
            positive ? Icons.check_rounded : Icons.schedule_rounded,
            color: positive
                ? const Color(0xFF14804A)
                : const Color(0xFFB26A00),
          ),
        ),
        title: Text(
          price,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(date + ' · ' + providerLabel),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _statusLabel(status),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: positive
                    ? const Color(0xFF14804A)
                    : const Color(0xFF667085),
              ),
            ),
            if (canResume) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF667085),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String value) {
    switch (value) {
      case 'approved':
        return 'Pagado';
      case 'rejected':
        return 'Rechazado';
      case 'cancelled':
        return 'Cancelado';
      case 'expired':
        return 'Vencido';
      case 'refunded':
        return 'Reembolsado';
      default:
        return 'Pendiente';
    }
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF0B57D0)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverSubscriptionMercadoPagoDialog extends StatefulWidget {
  final Map<String, dynamic> payment;
  final FutureOr<void> Function() onApproved;

  const _DriverSubscriptionMercadoPagoDialog({
    required this.payment,
    required this.onApproved,
  });

  @override
  State<_DriverSubscriptionMercadoPagoDialog> createState() =>
      _DriverSubscriptionMercadoPagoDialogState();
}

class _DriverSubscriptionMercadoPagoDialogState
    extends State<_DriverSubscriptionMercadoPagoDialog>
    with WidgetsBindingObserver {
  Timer? timer;
  bool checking = false;
  bool opening = false;
  String status = 'Completa el pago en Mercado Pago.';

  int get paymentId => _subscriptionInt(widget.payment['payment_id']);

  String get checkoutUrl =>
      widget.payment['checkout_url']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(_verify()),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_openCheckout()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_verify());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(String action) async {
    final response = await supabase.functions.invoke(
      'driver-subscription-payments',
      body: {'action': action, 'payment_id': paymentId},
    );
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    if (data['ok'] != true) {
      throw StateError(
        data['error']?.toString() ?? 'No se pudo verificar el pago',
      );
    }
    return data;
  }

  Future<void> _openCheckout() async {
    if (opening || checkoutUrl.isEmpty) return;
    setState(() => opening = true);
    try {
      final uri = Uri.tryParse(checkoutUrl);
      if (uri == null) {
        throw StateError('Mercado Pago devolvió un enlace inválido.');
      }
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('No se pudo abrir Mercado Pago.');
      }
      if (mounted) {
        setState(
          () => status =
              'Pago abierto en Mercado Pago. Al volver a Express verificaremos automáticamente.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> _verify() async {
    if (checking || paymentId <= 0) return;
    setState(() => checking = true);
    try {
      final data = await _call('verify');
      if (!mounted) return;
      if (data['approved'] == true) {
        timer?.cancel();
        setState(
          () => status =
              'Pago confirmado. Tu suscripción ya está activa.',
        );
        await widget.onApproved();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) Navigator.pop(context);
        return;
      }

      final raw = data['status']?.toString() ?? 'pending';
      final label = raw == 'pending'
          ? 'Pendiente'
          : raw == 'in_process'
              ? 'Procesando'
              : raw;
      setState(
        () => status =
            'Estado: ' + label + '. Express seguirá verificando el pago.',
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => status =
              'No pudimos confirmar todavía. Puedes volver a verificar.',
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _subscriptionPriceLabel(
      widget.payment['amount'],
      widget.payment['currency_code'],
    );

    return AlertDialog(
      title: const Text('Mercado Pago · Suscripción'),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 34,
              child: Icon(
                Icons.account_balance_wallet_rounded,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              amount,
              style: const TextStyle(
                color: Color(0xFF0B57D0),
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.35),
            ),
            const SizedBox(height: 10),
            const Text(
              'El pago se realiza en el sitio seguro de Mercado Pago. Al regresar a Express, la suscripción se activará cuando Mercado Pago confirme el pago.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        OutlinedButton.icon(
          onPressed: opening ? null : _openCheckout,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Abrir Mercado Pago'),
        ),
        FilledButton.icon(
          onPressed: checking ? null : _verify,
          icon: checking
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: const Text('Verificar pago'),
        ),
      ],
    );
  }
}

class _DriverSubscriptionQrDialog extends StatefulWidget {
  final Map<String, dynamic> payment;
  final FutureOr<void> Function() onApproved;

  const _DriverSubscriptionQrDialog({
    required this.payment,
    required this.onApproved,
  });

  @override
  State<_DriverSubscriptionQrDialog> createState() =>
      _DriverSubscriptionQrDialogState();
}

class _DriverSubscriptionQrDialogState
    extends State<_DriverSubscriptionQrDialog> {
  Timer? timer;
  bool checking = false;
  bool cancelling = false;
  String status = 'Esperando confirmación automática…';

  int get paymentId => _subscriptionInt(widget.payment['payment_id']);

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
      const Duration(seconds: 7),
      (_) => unawaited(_verify()),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(String action) async {
    final response = await supabase.functions.invoke(
      'driver-subscription-payments',
      body: {'action': action, 'payment_id': paymentId},
    );
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    if (data['ok'] != true) {
      throw StateError(
        data['error']?.toString() ?? 'No se pudo verificar',
      );
    }
    return data;
  }

  Future<void> _verify() async {
    if (checking || paymentId <= 0) return;
    setState(() => checking = true);
    try {
      final data = await _call('verify');
      if (!mounted) return;
      if (data['approved'] == true) {
        timer?.cancel();
        setState(() => status = 'Pago confirmado. Suscripción activada.');
        await widget.onApproved();
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (mounted) Navigator.pop(context);
        return;
      }
      setState(() {
        status = 'Pago ' +
            (data['status']?.toString() ?? 'pendiente') +
            ' · verificación automática activa';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => status =
              'Todavía no se pudo confirmar. Seguiremos verificando.',
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _cancel() async {
    if (cancelling) return;
    setState(() => cancelling = true);
    try {
      await _call('cancel');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    } finally {
      if (mounted) setState(() => cancelling = false);
    }
  }

  Widget _qrWidget() {
    final raw = widget.payment['qr']?.toString() ?? '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Image.network(
        raw,
        width: 285,
        height: 285,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const _QrUnavailable(),
      );
    }

    var encoded = raw;
    if (raw.startsWith('data:')) {
      final comma = raw.indexOf(',');
      if (comma >= 0) encoded = raw.substring(comma + 1);
    }
    try {
      final Uint8List bytes = base64Decode(
        encoded.replaceAll('\n', '').replaceAll(' ', ''),
      );
      return Image.memory(
        bytes,
        width: 285,
        height: 285,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const _QrUnavailable(),
      );
    } catch (_) {
      return const _QrUnavailable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('QR Bolivia · Suscripción'),
      content: SizedBox(
        width: 390,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(10),
                child: _qrWidget(),
              ),
              const SizedBox(height: 12),
              Text(
                'Bs ' + widget.payment['amount'].toString(),
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(status, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              const Text(
                'Puedes mantener esta ventana abierta. Express comprobará el pago automáticamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: cancelling ? null : _cancel,
          child: const Text('Cancelar pago'),
        ),
        FilledButton.icon(
          onPressed: checking ? null : _verify,
          icon: checking
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: const Text('Verificar ahora'),
        ),
      ],
    );
  }
}

class _QrUnavailable extends StatelessWidget {
  const _QrUnavailable();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 285,
      height: 285,
      child: Center(
        child: Text(
          'No se pudo mostrar el QR.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF667085)),
        ),
      ),
    );
  }
}

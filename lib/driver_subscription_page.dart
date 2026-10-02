import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';

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
            'id,plan_id,amount,currency_code,provider,status,created_at,paid_at,expires_at',
          )
          .order('created_at', ascending: false)
          .limit(30);

      if (!mounted) return;
      setState(() {
        state = data['state'] is Map
            ? Map<String, dynamic>.from(data['state'] as Map)
            : <String, dynamic>{};
        plans = _maps(data['plans']);
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

  String _money(Object? amount) {
    final value = amount is num
        ? amount.toDouble()
        : double.tryParse(amount?.toString() ?? '') ?? 0;
    final shown = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return 'Bs ' + shown;
  }

  List<String> _benefits(Map<String, dynamic> plan) {
    final raw = plan['benefits'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  Future<void> _buy(Map<String, dynamic> plan) async {
    if (state['provider_enabled'] != true) {
      _snack('QR Bolivia todavía está en configuración.');
      return;
    }
    try {
      _snack('Generando QR de pago…');
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
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DriverSubscriptionQrDialog(
          payment: data,
          onApproved: () => _load(silent: true),
        ),
      );
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
              state['provider_enabled'] == true
                  ? 'Paga con QR Bolivia. La activación se confirma automáticamente.'
                  : 'Los planes ya están configurados. El pago QR se habilitará al completar la conexión con VeriPagos.',
              style: const TextStyle(
                color: Color(0xFF667085),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            for (final plan in plans) ...[
              _PlanCard(
                plan: plan,
                price: _money(plan['amount']),
                benefits: _benefits(plan),
                enabled: state['provider_enabled'] == true,
                onBuy: () => _buy(plan),
              ),
              const SizedBox(height: 10),
            ],
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
                  price: _money(payment['amount']),
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
  final VoidCallback onBuy;

  const _PlanCard({
    required this.plan,
    required this.price,
    required this.benefits,
    required this.enabled,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final days = Number(plan['days'] ?? 0).toInt();
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
                icon: const Icon(Icons.qr_code_2_rounded),
                label: Text(
                  enabled ? 'Pagar con QR Bolivia' : 'QR en configuración',
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

  const _PaymentRow({
    required this.payment,
    required this.date,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    final status = payment['status']?.toString() ?? 'pending';
    final positive = status == 'approved';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
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
        subtitle: Text(date + ' · VeriPagos'),
        trailing: Text(
          _statusLabel(status),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: positive
                ? const Color(0xFF14804A)
                : const Color(0xFF667085),
          ),
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

  int get paymentId => Number(widget.payment['payment_id'] ?? 0).toInt();

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

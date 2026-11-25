import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'benefits_service.dart';
import 'benefit_audience_label.dart';
import 'core/runtime_channel.dart';
import 'money_format.dart';

class BenefitsPage extends StatefulWidget {
  const BenefitsPage({super.key, this.driver = false, this.initialModule = 'home'});
  final bool driver;
  final String initialModule;

  @override
  State<BenefitsPage> createState() => _BenefitsPageState();
}

class _BenefitsPageState extends State<BenefitsPage> {
  final _service = BenefitsService();
  late Future<Map<String, dynamic>> _future;
  late Future<Map<String, dynamic>> _referralFuture;
  final _referralCode = TextEditingController();
  bool _referralSaving = false;
  String? _joiningChallengeId;
  late String _selectedModule;
  String _challengeTab = 'available';

  String get _role => widget.driver ? 'driver' : 'passenger';

  bool _audienceAllowed(Map<String, dynamic> item) {
    final config = item['config'];
    final audience = config is Map ? config['audience']?.toString() : null;
    if (audience == null || audience.isEmpty || audience == 'all') return true;
    if (audience == 'clients') return !widget.driver;
    return audience == (widget.driver ? 'drivers' : 'passengers');
  }

  @override
  void initState() {
    super.initState();
    _selectedModule = widget.initialModule;
    _future = _service.overview(role: _role);
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
        _future = _service.overview(role: _role);
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
        content: Text('Código de referido registrado. Tu recompensa se activará según las condiciones del programa.'),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo registrar el código. Verifica que sea válido y que el programa esté activo en tu zona.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _referralSaving = false);
    }
  }

  String _label(String type) => switch (type) {
        'coupon' => 'Cupones',
        'activation' => 'Bienvenida y recompensas',
        'loyalty' => 'Fidelidad',
        'referral' => 'Invita y gana',
        'driver_challenge' => 'Retos de conductor',
        _ => 'Beneficio Express',
      };

  IconData _icon(String type) => switch (type) {
        'coupon' => Icons.local_offer_outlined,
        'activation' => Icons.card_giftcard_outlined,
        'loyalty' => Icons.stars_outlined,
        'referral' => Icons.people_alt_outlined,
        'driver_challenge' => Icons.flag_outlined,
        _ => Icons.redeem_outlined,
      };

  String _challengePeriod(Map<String, dynamic> config) => switch (config['period']?.toString()) {
        'daily' => 'Diario',
        'weekly' => 'Semanal',
        'monthly' => 'Mensual',
        _ => 'Personalizado',
      };

  String _challengeDate(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return 'Sin fecha de fin';
    return '${date.day.toString().padLeft(2, '0')} ${_monthShort(date.month)}';
  }

  String _monthShort(int month) => const [
        '', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
        'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
      ][month];

  Widget _challengeCard(BuildContext context, Map<String, dynamic> item,
      {bool completed = false}) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleSurface = dark ? const Color(0xFF183226) : const Color(0xFFF0FDF4);
    final rewardColor = dark ? const Color(0xFF86EFAC) : const Color(0xFF15803D);
    final exclusiveColor = dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    final config = item['config'] is Map
        ? Map<String, dynamic>.from(item['config'] as Map)
        : <String, dynamic>{};
    final challenge = item['challenge'] is Map
        ? Map<String, dynamic>.from(item['challenge'] as Map)
        : const <String, dynamic>{};
    final goal = (challenge['goal'] ?? config['trip_goal'] ?? config['trip_threshold'] ?? 0) as num? ?? 0;
    final progress = (challenge['completed_trips'] as num?)?.toDouble() ?? 0;
    final reward = config['reward_type'] == 'commission_free'
        ? '${config['commission_free_trips'] ?? config['value'] ?? 0} viajes sin comisión'
        : 'Bono ${expressMoney(config['value'], item['currency']?.toString())}';
    final goalValue = goal.toDouble();
    final progressValue = goalValue <= 0
        ? 0.0
        : (progress / goalValue).clamp(0.0, 1.0).toDouble();
    final isEnrolled = challenge['enrolled'] == true;
    final exclusive = config['exclusive'] == true;
    final startsAt = item['starts_at'];
    final endsAt = item['ends_at'];
    final period = _challengePeriod(config);
    final title = item['name']?.toString() ?? 'Reto de viajes';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: titleSurface,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            Icon(Icons.emoji_events_outlined, color: rewardColor, size: 20),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: scheme.onSurface)),
              if ((item['description']?.toString().trim() ?? '').isNotEmpty)
                Text(item['description'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ])),
            Text(period, style: TextStyle(fontSize: 10, color: rewardColor, fontWeight: FontWeight.w800)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Row(children: [
                Icon(Icons.flag_outlined, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text('${goal.toInt()} viajes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              ])),
              Expanded(child: Row(children: [
                Icon(Icons.card_giftcard_outlined, size: 15, color: rewardColor),
                const SizedBox(width: 5),
                Expanded(child: Text(reward, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: rewardColor, fontWeight: FontWeight.w700))),
              ])),
            ]),
            const SizedBox(height: 9),
            Row(children: [
              Icon(Icons.calendar_month_outlined, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Expanded(child: Text(startsAt == null && endsAt == null
                  ? 'Periodo: $period'
                  : '${startsAt == null ? 'Inicio activo' : _challengeDate(startsAt)} – ${endsAt == null ? 'Sin fecha de fin' : _challengeDate(endsAt)}',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))),
              if (exclusive) Text('★ Reto exclusivo', style: TextStyle(fontSize: 10, color: exclusiveColor, fontWeight: FontWeight.w700)),
            ]),
            if (isEnrolled || completed) ...[
              const SizedBox(height: 11),
              Row(children: [
                Expanded(child: Text(completed ? 'Reto completado' : '$progress de ${goal.toInt()} viajes',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurface))),
                Text('${(progressValue * 100).round()}%', style: const TextStyle(fontSize: 11, color: Color(0xFF1769E0), fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: completed ? 1.0 : progressValue, minHeight: 7)),
              const SizedBox(height: 7),
              Text(completed ? 'La recompensa se procesa según las reglas del reto.' : 'Faltan ${(goalValue - progress).ceil().clamp(0, 999999)} viajes para completar',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ] else ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: _joiningChallengeId == item['id']?.toString()
                      ? null
                      : () => _joinChallenge(context, item['id']?.toString() ?? ''),
                  child: Text(_joiningChallengeId == item['id']?.toString() ? 'Inscribiendo…' : 'Inscribirme'),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _driverChallenges(BuildContext context, List<Map<String, dynamic>> items,
      List<Map<String, dynamic>> history, Map<String, dynamic> data) {
    final scheme = Theme.of(context).colorScheme;
    final challenges = items.where((item) => item['type'] == 'driver_challenge').toList();
    final available = challenges.where((item) {
      final challenge = item['challenge'];
      return challenge is! Map || challenge['enrolled'] != true;
    }).toList();
    final mine = challenges.where((item) {
      final challenge = item['challenge'];
      if (challenge is! Map || challenge['enrolled'] != true) return false;
      final config = item['config'] is Map
          ? Map<String, dynamic>.from(item['config'] as Map)
          : const <String, dynamic>{};
      final goal = (challenge['goal'] ?? config['trip_goal'] ?? config['trip_threshold'] ?? 0) as num? ?? 0;
      final progress = (challenge['completed_trips'] as num?) ?? 0;
      return progress < goal;
    }).toList();
    final completed = challenges.where((item) {
      final challenge = item['challenge'];
      if (challenge is! Map || challenge['enrolled'] != true) return false;
      final config = item['config'] is Map ? item['config'] as Map : const {};
      final goal = (challenge['goal'] ?? config['trip_goal'] ?? config['trip_threshold'] ?? 0) as num? ?? 0;
      return goal > 0 && ((challenge['completed_trips'] as num?) ?? 0) >= goal;
    }).toList();
    final historyRows = history.where((row) =>
      (row['benefit_type']?.toString() ?? '').toLowerCase().contains('challenge') ||
      (row['benefit_type']?.toString() ?? '').toLowerCase().contains('reto')).toList();
    final rows = switch (_challengeTab) {
      'mine' => mine,
      'history' => completed,
      _ => available,
    };

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(padding: const EdgeInsets.fromLTRB(0, 0, 0, 18), children: [
        Container(
          color: scheme.surface,
          child: Row(children: [
            for (final tab in const [('available', 'Disponibles'), ('mine', 'Mis Retos'), ('history', 'Historial')])
              Expanded(child: InkWell(
                onTap: () => setState(() => _challengeTab = tab.$1),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _challengeTab == tab.$1 ? scheme.primary : Colors.transparent, width: 2))),
                  child: Text(tab.$2, style: TextStyle(fontSize: 12, fontWeight: _challengeTab == tab.$1 ? FontWeight.w800 : FontWeight.w600, color: _challengeTab == tab.$1 ? scheme.primary : scheme.onSurfaceVariant)),
                ),
              )),
          ]),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty && _challengeTab == 'history' && historyRows.isNotEmpty)
          ...historyRows.map((row) => Card(margin: const EdgeInsets.fromLTRB(14, 0, 14, 9), child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
            title: Text(row['benefit_type']?.toString() ?? 'Reto completado'),
            subtitle: Text(row['state']?.toString() ?? 'Recompensa'),
            trailing: Text(expressMoney(row['amount'], data['currency']?.toString() ?? 'BOB')),
          )))
        else if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(
            _challengeTab == 'available' ? 'No hay retos disponibles en este momento.' :
            _challengeTab == 'mine' ? 'Todavía no te has inscrito en un reto.' : 'Todavía no hay retos completados.',
            textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant),
          )))
        else
          ...rows.map((item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _challengeCard(context, item, completed: _challengeTab == 'history'),
          )),
      ]),
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> item) {
    final config = item['config'] is Map
        ? Map<String, dynamic>.from(item['config'] as Map)
        : <String, dynamic>{};
    final description = item['description']?.toString().trim() ?? '';
    final code = config['code']?.toString();
    final amount = config['value'];
    final kind = config['discount_type']?.toString();
    final isChallenge = item['type'] == 'driver_challenge' && widget.driver;
    final challenge = item['challenge'] is Map
        ? Map<String, dynamic>.from(item['challenge'] as Map)
        : const <String, dynamic>{};
    final enrolled = challenge['enrolled'] == true;
    final challengeGoal = challenge['goal'] ?? config['trip_goal'] ?? config['trip_threshold'] ?? 0;
    final challengeProgress = challenge['completed_trips'] ?? 0;
    final challengeReward = config['reward_type'] == 'commission_free'
        ? '${config['commission_free_trips'] ?? config['value'] ?? 0} viajes sin comisión'
        : 'Bono ${expressMoney(config['value'], item['currency']?.toString())}';
    final detail = isChallenge
        ? '$challengeGoal viajes · ${config['period'] ?? 'semanal'} · $challengeReward'
        : amount == null
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
              const SizedBox(height: 2),
              Text('Dirigido a: ${benefitAudienceLabel(config['audience'])}',
                  style: const TextStyle(color: Color(0xFF667085), fontSize: 12, fontWeight: FontWeight.w600)),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(color: Color(0xFF667085))),
              ],
              if (isChallenge && enrolled) ...[
                const SizedBox(height: 6),
                Text('Inscrito · $challengeProgress de $challengeGoal viajes completados',
                    style: const TextStyle(color: Color(0xFF1769E0), fontWeight: FontWeight.w700)),
              ],
              if (isChallenge && !enrolled) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: _joiningChallengeId == item['id']?.toString()
                        ? null
                        : () => _joinChallenge(context, item['id']?.toString() ?? ''),
                    child: Text(_joiningChallengeId == item['id']?.toString() ? 'Inscribiendo…' : 'Inscribirme'),
                  ),
                ),
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

  Future<void> _joinChallenge(BuildContext context, String programId) async {
    if (programId.isEmpty || _joiningChallengeId != null) return;
    setState(() => _joiningChallengeId = programId);
    try {
      await _service.joinDriverChallenge(programId);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Te inscribiste en el reto.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo inscribir: $error')));
      }
    } finally {
      if (mounted) setState(() => _joiningChallengeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.driver ? 'Conductor' : 'Pasajero';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.driver && _selectedModule == 'driver_challenge' ? 'Retos' : 'Beneficios Express', style: const TextStyle(fontWeight: FontWeight.w900)),
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
          final coupons = data['coupons'] is List
              ? (data['coupons'] as List).whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row)).toList()
              : <Map<String, dynamic>>[];
          final modules = widget.driver
              ? const [('home', 'Vista general'), ('referral', 'Referidos'), ('driver_challenge', 'Retos'), ('wallet', 'Billetera')]
              : const [('home', 'Vista general'), ('coupon', 'Cupones'), ('activation', 'Reglas'), ('loyalty', 'Fidelidad')];
          // Respaldo en la app: no mostrar programas de otro público.
          final allowedItems = items.where(_audienceAllowed).toList();
          final displayedItems = _selectedModule == 'home'
              ? allowedItems
              : allowedItems.where((item) => item['type'] == _selectedModule).toList();
          if (widget.driver && _selectedModule == 'driver_challenge') {
            return _driverChallenges(context, allowedItems, history, data);
          }
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: modules.map((module) => ChoiceChip(
                  label: Text(module.$2),
                  selected: _selectedModule == module.$1,
                  onSelected: (_) => setState(() => _selectedModule = module.$1),
                )).toList(),
              ),
              const SizedBox(height: 18),
              if (_selectedModule == 'home') ...[
                Text(widget.driver ? 'Programas para conductores' : 'Para ti',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.65,
                  children: modules.where((module) => module.$1 != 'home').map((module) => Card(
                    child: InkWell(
                      onTap: () => setState(() => _selectedModule = module.$1),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(_moduleIcon(module.$1), color: const Color(0xFF1769E0)),
                          const SizedBox(height: 6),
                          Text(module.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  )).toList(),
                ),
              ] else
                Text(modules.firstWhere((module) => module.$1 == _selectedModule).$2,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              if (_selectedModule == 'coupon' && !widget.driver) ...[
                const Text('Mis cupones', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                if (coupons.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Cuando ganes un viaje gratis, tu cupón aparecerá aquí.')))
                else
                  ...coupons.map((coupon) => _userCouponCard(context, coupon)),
                const SizedBox(height: 8),
              ],
              if (widget.driver && (_selectedModule == 'home' || _selectedModule == 'referral'))
                FutureBuilder<Map<String, dynamic>>(
                  future: _referralFuture,
                  builder: (context, referralSnapshot) {
                    final referral = referralSnapshot.data ?? const <String, dynamic>{};
                    final code = referral['code']?.toString() ?? '';
                    final referralMessage = referral['program_active'] != true
                        ? 'No hay un programa de referidos activo en esta zona.'
                        : referral['program_type'] == 'referral'
                        ? 'Recibe la recompensa configurada cuando tu referido complete ${referral['min_paid_trips'] ?? 1} viajes pagados.'
                        : referral['commission_basis'] == 'company_trip'
                            ? 'Recibe ${referral['percent'] ?? 0}% de la comisión de Express por cada viaje pagado de tu referido.'
                            : 'Recibe la comisión configurada cuando tu referido pague un plan.';
                    return Card(child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Invita a otro conductor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Text(referralMessage),
                        if (referral['eligible'] == false)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('Necesitas un perfil de conductor con una zona activa para participar.'),
                          ),
                        if (referral['program_active'] == true && code.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: SelectableText('Tu código: $code', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
                            IconButton(tooltip: 'Copiar código', onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: code));
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado.')));
                            }, icon: const Icon(Icons.copy_rounded)),
                          ]),
                          Text('${referral['referrals'] ?? 0} conductores referidos · ${expressMoney(referral['credited_total'], referral['currency']?.toString() ?? 'BOB')} acreditados', style: const TextStyle(color: Color(0xFF667085))),
                        ],
                        if (referral['program_active'] == true && referral['eligible'] != false && referral['has_referrer'] == true)
                          const Padding(padding: EdgeInsets.only(top: 12), child: Text('Ya tienes un conductor invitador registrado.'))
                        else if (referral['program_active'] == true && referral['eligible'] != false) ...[
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
                          const Text('No se pudieron cargar los referidos. Comprueba tu conexión e inténtalo nuevamente.', style: TextStyle(color: Color(0xFF667085))),
                      ]),
                    ));
                  },
                ),
              if (_selectedModule == 'wallet') ...[
                const Text('Historial de beneficios', style: TextStyle(fontWeight: FontWeight.w800)),
                if (history.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Todavía no hay movimientos de beneficios.')))
                else
                  ...history.map((item) => ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(item['benefit_type']?.toString() ?? 'Beneficio'),
                    subtitle: Text(item['state']?.toString() ?? 'Pendiente'),
                    trailing: Text(expressMoney(item['amount'], data['currency']?.toString() ?? 'BOB')),
                  )),
              ],
              if (_selectedModule != 'wallet' && displayedItems.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Todavía no hay beneficios activos en esta sección y zona.'),
                ))
              else if (_selectedModule != 'wallet')
                ...displayedItems.map((item) => _card(context, item)),
              if (_selectedModule == 'home' && history.isNotEmpty) ...[
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

  IconData _moduleIcon(String module) => switch (module) {
        'coupon' => Icons.local_offer_outlined,
        'activation' => Icons.bolt_outlined,
        'loyalty' => Icons.stars_outlined,
        'referral' => Icons.people_alt_outlined,
        'challenges' || 'driver_challenge' => Icons.flag_outlined,
        'wallet' => Icons.account_balance_wallet_outlined,
        _ => Icons.card_giftcard_outlined,
      };

  Widget _userCouponCard(BuildContext context, Map<String, dynamic> coupon) {
    final code = coupon['code']?.toString() ?? '';
    final value = coupon['value'];
    final percent = coupon['discount_type'] == 'percent';
    final cap = coupon['max_discount'];
    final expires = DateTime.tryParse(coupon['expires_at']?.toString() ?? '');
    final expiry = expires == null
        ? ''
        : 'Vence ${expires.day.toString().padLeft(2, '0')}/${expires.month.toString().padLeft(2, '0')}/${expires.year}';
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.card_giftcard_outlined)),
        title: Text(coupon['name']?.toString() ?? 'Viaje gratis', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${percent ? '$value%' : expressMoney(value, coupon['currency']?.toString())}${cap == null ? '' : ' · hasta ${expressMoney(cap, coupon['currency']?.toString())}'}${expiry.isEmpty ? '' : ' · $expiry'}\nCódigo: $code. Úsalo al solicitar el viaje en efectivo o QR del conductor.'),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Copiar código',
          onPressed: code.isEmpty ? null : () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado.')));
          },
          icon: const Icon(Icons.copy_rounded),
        ),
        onTap: code.isEmpty ? null : () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado.')));
        },
      ),
    );
  }
}

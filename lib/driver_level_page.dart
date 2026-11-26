import 'package:flutter/material.dart';

import 'core/runtime_channel.dart';
import 'driver_priority_page.dart';
import 'services/express_service.dart';

/// «Mi nivel»: Inicio, Pro o Élite según los últimos 30 días, y lo que falta para subir.
/// El nivel pesa en quién recibe primero los avisos de precio fijo y en el orden de la lista de solicitudes.

const _levelColors = {
  'inicio': Color(0xFF667085),
  'pro': Color(0xFF2563EB),
  'elite': Color(0xFF7C3AED),
};

String driverLevelLabel(String? level) => switch (level) {
      'elite' => 'Élite',
      'pro' => 'Pro',
      _ => 'Inicio',
    };

/// Texto de un criterio: «12 de 30 viajes», «4.9 de 4.85 estrellas», «20 % (máximo 15 %)».
String driverLevelCriterionText(Map<String, dynamic> c) {
  final unit = c['unit']?.toString() ?? '';
  final value = c['value'];
  final target = c['target'];
  final higher = c['higher_is_better'] != false;
  String v(Object? x) => x == null ? '—' : x.toString().replaceAll(RegExp(r'\.0+$'), '');
  final suffix = unit == '%' ? ' %' : (unit.isEmpty ? '' : ' $unit');
  return higher
      ? '${v(value)} de ${v(target)}$suffix'
      : '${v(value)}${unit == '%' ? ' %' : ''} (máximo ${v(target)}${unit == '%' ? ' %' : ''})';
}

/// Avance 0..1 hacia el objetivo de un criterio.
double driverLevelCriterionProgress(Map<String, dynamic> c) {
  if (c['met'] == true) return 1;
  final value = (c['value'] as num?)?.toDouble();
  final target = (c['target'] as num?)?.toDouble();
  if (value == null || target == null || target <= 0) return 0;
  if (c['higher_is_better'] == false) return 0.2;
  return (value / target).clamp(0.0, 1.0);
}

class DriverLevelPage extends StatefulWidget {
  final ExpressService service;
  const DriverLevelPage({super.key, required this.service});

  @override
  State<DriverLevelPage> createState() => _DriverLevelPageState();
}

class _DriverLevelPageState extends State<DriverLevelPage> {
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = widget.service.myDriverLevel();
  }

  void _reload() => setState(() => future = widget.service.myDriverLevel());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi nivel'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  ExpressRuntimeChannel.userSafeError(
                    snap.error,
                    fallback: 'No se pudo cargar tu nivel.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final data = snap.data ?? const <String, dynamic>{};
          if (data['enabled'] == false) {
            return const Center(child: Text('Los niveles no están disponibles todavía.'));
          }
          final level = data['level']?.toString() ?? 'inicio';
          final next = data['next_level']?.toString();
          final days = (data['window_days'] as num?)?.toInt() ?? 30;
          final m = data['metrics'] is Map
              ? Map<String, dynamic>.from(data['metrics'] as Map)
              : <String, dynamic>{};
          final criteria = (data['criteria'] as List? ?? const [])
              .whereType<Map>()
              .map((c) => Map<String, dynamic>.from(c))
              .toList();
          final color = _levelColors[level] ?? _levelColors['inicio']!;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.military_tech_rounded, size: 44, color: color),
                    const SizedBox(height: 6),
                    Text(
                      driverLevelLabel(level),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Según tus últimos $days días: ${m['trips'] ?? 0} viajes',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    if (next == null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Estás en el nivel más alto. Mantén tu ritmo para conservarlo.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              if (next != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Para llegar a ${driverLevelLabel(next)}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      for (final c in criteria) _CriterionRow(criterion: c),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Tu nivel se calcula con los últimos $days días. Responder a las solicitudes que ves, '
                  'cancelar poco y mantener una buena calificación te ayuda a subir. '
                  'Con nivel Élite o Pro recibes primero los avisos de viajes de precio fijo entre los conductores '
                  'que están casi igual de cerca del pasajero, y tu lista de solicitudes se ordena a tu favor.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DriverPriorityPage(service: widget.service),
                  ),
                ),
                icon: const Icon(Icons.format_list_numbered_rounded),
                label: const Text('Cómo se ordenan mis solicitudes'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  final Map<String, dynamic> criterion;
  const _CriterionRow({required this.criterion});

  @override
  Widget build(BuildContext context) {
    final met = criterion['met'] == true;
    final color = met ? const Color(0xFF15803D) : const Color(0xFFB45309);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(criterion['label']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text(driverLevelCriterionText(criterion),
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: driverLevelCriterionProgress(criterion),
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

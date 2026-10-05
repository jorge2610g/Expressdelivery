import 'package:flutter/material.dart';

import 'core/runtime_channel.dart';

import 'services/express_service.dart';

class DriverPriorityPage extends StatefulWidget {
  final ExpressService service;

  const DriverPriorityPage({
    super.key,
    required this.service,
  });

  @override
  State<DriverPriorityPage> createState() => _DriverPriorityPageState();
}

class _DriverPriorityPageState extends State<DriverPriorityPage> {
  static const _green = Color(0xFF16A34A);
  static const _orange = Color(0xFFF59E0B);
  static const _red = Color(0xFFDC2626);
  static const _ink = Color(0xFF101828);
  static const _muted = Color(0xFF667085);

  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = widget.service.myDriverPrioritySummary();
  }

  void _refresh() {
    setState(() {
      future = widget.service.myDriverPrioritySummary();
    });
  }

  double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _levelLabel(String raw) {
    switch (raw) {
      case 'high':
        return 'Alta';
      case 'medium':
        return 'Media';
      default:
        return 'Baja';
    }
  }

  Color _levelColor(String raw) {
    switch (raw) {
      case 'high':
        return _green;
      case 'medium':
        return _orange;
      default:
        return _red;
    }
  }

  String _levelHelp(String raw) {
    switch (raw) {
      case 'high':
        return 'Tu perfil tiene prioridad para mostrar primero solicitudes cercanas, bien pagadas y con pasajeros de buena reputación.';
      case 'medium':
        return 'Recibes solicitudes normales. Mejorar reseñas, actividad y experiencia aumenta tu prioridad.';
      default:
        return 'Tu prioridad es baja. Completar más viajes y mantener buenas calificaciones ayuda a subir de nivel.';
    }
  }

  Widget _metric({
    required String label,
    required double value,
    required IconData icon,
  }) {
    final normalized = value.clamp(0, 100).toDouble();
    final color = normalized >= 75
        ? _green
        : normalized >= 50
            ? _orange
            : _red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              normalized.toStringAsFixed(0) + '%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: normalized / 100,
            minHeight: 8,
            backgroundColor: const Color(0xFFF2F4F7),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'Mi prioridad',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  ExpressRuntimeChannel.userSafeError(
                    snapshot.error,
                    fallback: 'No pudimos cargar tu prioridad.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data ?? const <String, dynamic>{};
          if (data['reason'] == 'not_driver') {
            return const Center(
              child: Text('Esta sección es solo para conductores.'),
            );
          }

          final level = data['level']?.toString() ?? 'low';
          final levelColor = _levelColor(level);
          final score = _num(data['score']);
          final enabled = data['enabled'] == true;
          final enforcement = data['enforcement_enabled'] == true;
          final metrics = data['metrics'] is Map
              ? Map<String, dynamic>.from(data['metrics'] as Map)
              : <String, dynamic>{};

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Prioridad',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: enabled
                                  ? const Color(0xFFE8F8EF)
                                  : const Color(0xFFF2F4F7),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              enabled ? 'Activo' : 'Desactivado',
                              style: TextStyle(
                                color: enabled ? _green : _muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _levelLabel(level),
                        style: TextStyle(
                          color: levelColor,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Puntaje ${score.toStringAsFixed(1)} / 100',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _levelHelp(level),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _muted,
                          height: 1.4,
                        ),
                      ),
                      if (!enforcement) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7E8),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'El ranking está visible, pero el filtro de despacho todavía está desactivado para este canal.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF9A6700),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      _metric(
                        label: 'Reputación',
                        value: _num(metrics['rating']),
                        icon: Icons.star_rounded,
                      ),
                      const SizedBox(height: 18),
                      _metric(
                        label: 'Reseñas',
                        value: _num(metrics['reviews']),
                        icon: Icons.reviews_rounded,
                      ),
                      const SizedBox(height: 18),
                      _metric(
                        label: 'Experiencia',
                        value: _num(metrics['experience']),
                        icon: Icons.workspace_premium_rounded,
                      ),
                      const SizedBox(height: 18),
                      _metric(
                        label: 'Frecuencia de viajes',
                        value: _num(metrics['frequency']),
                        icon: Icons.route_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        value: (data['completed_trips'] ?? 0).toString(),
                        label: 'viajes',
                        icon: Icons.local_taxi_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        value: (data['review_count'] ?? 0).toString(),
                        label: 'reseñas',
                        icon: Icons.star_border_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        color: Color(0xFF1769E0),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Las calificaciones son privadas. Aquí solo ves tu resumen y nivel; no se muestra quién te calificó.',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF1769E0)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

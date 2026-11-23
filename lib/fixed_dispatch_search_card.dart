import 'dart:async';

import 'package:flutter/material.dart';

import 'driver_portrait.dart';
import 'services/express_service.dart';

/// Texto de la cuenta regresiva `00:15`.
String fixedDispatchClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// Búsqueda de conductor en un servicio de precio fijo: se ofrece el viaje al
/// conductor más cercano, uno por vez. Muestra quién está respondiendo, el
/// tiempo que le queda y, si nadie acepta, permite volver a buscar.
class FixedDispatchSearchCard extends StatefulWidget {
  const FixedDispatchSearchCard({
    super.key,
    required this.service,
    required this.ride,
    required this.onCancel,
    this.onExpired,
    this.onAdvanced,
  });

  final ExpressService service;
  final Map<String, dynamic> ride;
  final VoidCallback onCancel;

  /// Se llama cuando el pasajero no decidió a tiempo y el viaje se canceló solo:
  /// la pantalla vuelve al inicio.
  final VoidCallback? onExpired;

  /// Se llama en cuanto un conductor tomó el viaje: la pantalla del pasajero
  /// se actualiza al instante, sin esperar al sondeo general.
  final VoidCallback? onAdvanced;

  @override
  State<FixedDispatchSearchCard> createState() =>
      _FixedDispatchSearchCardState();
}

class _FixedDispatchSearchCardState extends State<FixedDispatchSearchCard> {
  Timer? _poll;
  bool _advancedNotified = false;
  Timer? _clock;
  Map<String, dynamic> _state = const {};
  DateTime _deadline = DateTime.now().toUtc();
  int _secondsLeft = 0;
  // Segundos que tiene cada conductor (los fija el servidor; se toma el mayor visto).
  int _perDriverTotal = 30;
  // Minuto total de búsqueda (el servidor manda cuánto queda).
  DateTime? _windowEnd;
  int _windowLeft = 0;
  // Tiempo para decidir (seguir o cancelar) cuando terminaron los 3 minutos.
  static const int _decisionTotal = 30;
  DateTime? _decisionEnd;
  int _decisionLeft = _decisionTotal;
  bool _expiredNotified = false;
  bool _restarting = false;
  bool _failed = false;

  String get _rideId => widget.ride['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _deadline.difference(DateTime.now().toUtc()).inSeconds;
      if (_decisionEnd != null) {
        final dl = _decisionEnd!.difference(DateTime.now().toUtc()).inSeconds;
        final d = dl < 0 ? 0 : dl;
        if (d != _decisionLeft) setState(() => _decisionLeft = d);
        if (d <= 0) _notifyExpired();
      }
      final windowLeft = _windowEnd == null
          ? 0
          : _windowEnd!.difference(DateTime.now().toUtc()).inSeconds;
      final w = windowLeft < 0 ? 0 : windowLeft;
      if (left != _secondsLeft || w != _windowLeft) {
        setState(() {
          _secondsLeft = left < 0 ? 0 : left;
          _windowLeft = w;
        });
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _notifyExpired() {
    if (_expiredNotified) return;
    _expiredNotified = true;
    widget.onExpired?.call();
  }

  Future<void> _refresh() async {
    if (_rideId.isEmpty) return;
    try {
      final state = await widget.service.fixedDispatchState(_rideId);
      if (!mounted) return;
      final current = state['current'];
      final expiresAt = current is Map
          ? DateTime.tryParse(current['expires_at']?.toString() ?? '')?.toUtc()
          : null;
      final windowSeconds = (state['window_seconds_left'] as num?)?.toInt();
      final decisionSeconds = (state['decision_seconds_left'] as num?)?.toInt();
      final rideStatus = state['ride_status']?.toString();
      if (rideStatus == 'cancelled' || rideStatus == 'expired') {
        _notifyExpired();
      } else if (rideStatus != null &&
          rideStatus != 'pending' &&
          !_advancedNotified) {
        // 'driver_selected' u otro estado posterior: un conductor aceptó.
        _advancedNotified = true;
        widget.onAdvanced?.call();
      }
      setState(() {
        _state = state;
        _failed = false;
        _windowEnd = windowSeconds == null
            ? null
            : DateTime.now().toUtc().add(Duration(seconds: windowSeconds));
        _windowLeft = windowSeconds ?? 0;
        _decisionEnd = decisionSeconds == null
            ? null
            : DateTime.now().toUtc().add(Duration(seconds: decisionSeconds));
        _decisionLeft = decisionSeconds ?? _decisionTotal;
        if (expiresAt != null) {
          _deadline = expiresAt;
          final left = expiresAt.difference(DateTime.now().toUtc()).inSeconds;
          _secondsLeft = left < 0 ? 0 : left;
          if (_secondsLeft > _perDriverTotal) _perDriverTotal = _secondsLeft;
        } else {
          _secondsLeft = 0;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _restart() async {
    if (_restarting) return;
    setState(() => _restarting = true);
    try {
      await widget.service.restartFixedDispatch(_rideId);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo volver a buscar. Inténtalo de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _state['current'] is Map
        ? Map<String, dynamic>.from(_state['current'] as Map)
        : null;
    final previous = _state['previous'] is Map
        ? Map<String, dynamic>.from(_state['previous'] as Map)
        : null;
    final exhausted = _state['exhausted'] == true && current == null;

    late final String title;
    late final String subtitle;
    if (exhausted) {
      // Terminaron los 3 minutos: el pasajero decide si sigue o cancela.
      title = '¿Seguimos buscando conductor?';
      subtitle = 'Pasaron 3 minutos y ningún conductor tomó tu viaje. '
          'Puedes buscar otros 3 minutos o cancelar el viaje.';
    } else if (current != null) {
      title = 'El conductor está respondiendo';
      subtitle = 'Tiene unos segundos para aceptar tu viaje';
    } else {
      // Nadie disponible por ahora: seguimos esperando a que se conecte alguien.
      title = 'Buscando conductor cerca de ti';
      subtitle = 'Te avisamos en cuanto un conductor tome tu viaje';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900)),
            ),
            if (current != null)
              Text(fixedDispatchClock(_secondsLeft),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800))
            else if (!exhausted && _windowEnd != null)
              Text(fixedDispatchClock(_windowLeft),
                  key: const ValueKey('fixed-window-clock'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 12.5)),
        if (current != null && previous != null) ...[
          const SizedBox(height: 4),
          const Text(
            'El conductor anterior no estaba disponible. Ya estamos buscando otro.',
            style: TextStyle(fontSize: 12, color: Color(0xFFB54708)),
          ),
        ],
        if (current != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              ExpressDriverPortrait(
                key: ValueKey('fixed-${current['driver_id']}'),
                driverId: current['driver_id']?.toString(),
                approvedPath: current['profile_photo_path']?.toString(),
                fallbackUrl: current['avatar_url']?.toString(),
                radius: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${current['full_name'] ?? 'Conductor'}'
                      '${current['rating'] != null ? '  ★ ${(current['rating'] as num).toStringAsFixed(2)}' : ''}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    if ((current['vehicle_summary'] ?? '').toString().isNotEmpty)
                      Text(current['vehicle_summary'].toString(),
                          style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: _secondsLeft <= 0
                  ? 0
                  : (_secondsLeft / _perDriverTotal).clamp(0.0, 1.0),
              minHeight: 5,
            ),
          ),
        ] else if (!exhausted) ...[
          const SizedBox(height: 12),
          const ClipRRect(child: LinearProgressIndicator(minHeight: 5)),
        ],
        if (exhausted) ...[
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Se cancelará automáticamente en $_decisionLeft s',
                  key: const ValueKey('fixed-decision-countdown'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (_decisionLeft / _decisionTotal).clamp(0.0, 1.0),
              minHeight: 5,
            ),
          ),
        ],
        if (_failed)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Reconectando…', style: TextStyle(fontSize: 12)),
          ),
        const SizedBox(height: 12),
        if (exhausted)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _restarting ? null : _restart,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_restarting ? 'Buscando…' : 'Seguir buscando'),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancelar viaje'),
          ),
        ),
      ],
    );
  }
}

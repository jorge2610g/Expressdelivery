import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_error_reporter.dart';
import 'core/supabase_client.dart';
import 'push_notifications.dart';

/// Si las notificaciones del teléfono están bloqueadas, avisa con una hoja
/// amable (como máximo una vez cada 3 días) y ofrece abrir los ajustes. Al
/// volver de los ajustes registra el dispositivo. Además renueva el registro
/// del dispositivo al volver a la app (como máximo cada 6 horas) para
/// recuperar los que quedaron inválidos.
class PushPermissionPrompt extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const PushPermissionPrompt({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<PushPermissionPrompt> createState() => _PushPermissionPromptState();
}

class _PushPermissionPromptState extends State<PushPermissionPrompt>
    with WidgetsBindingObserver {
  static const _snoozeDays = 3;
  static const _refreshHours = 6;

  bool _sheetOpen = false;
  bool _awaitingSettings = false;
  Timer? _firstCheck;

  bool get _active => widget.enabled && !kIsWeb;

  String get _uid => supabase.auth.currentUser?.id ?? 'anon';
  String get _snoozeKey => 'express_push_prompt_snooze_v1_$_uid';
  String get _refreshKey => 'express_push_refresh_v1_$_uid';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Se espera un poco para no tapar la primera pantalla.
    _firstCheck = Timer(const Duration(seconds: 8), _check);
  }

  @override
  void dispose() {
    _firstCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
    }
  }

  Future<void> _onResumed() async {
    if (!_active || !mounted) return;
    if (_awaitingSettings) {
      _awaitingSettings = false;
      final state = await pushPermissionState();
      if (state == 'granted') {
        await _register();
        unawaited(AppErrorReporter.event(
          'PUSH_PROMPT_ENABLED_FROM_SETTINGS',
          source: 'push_permission_prompt',
          screen: 'push',
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Listo, activaste las notificaciones.'),
          ));
        }
        return;
      }
    }
    await _refreshRegistrationIfDue();
  }

  Future<void> _register() async {
    final token = supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return;
    await enablePushNotifications(token);
  }

  /// Renueva el registro del dispositivo si ya tiene permiso (cada 6 h como máximo).
  Future<void> _refreshRegistrationIfDue() async {
    try {
      final state = await pushPermissionState();
      if (state != 'granted') return;
      final prefs = await SharedPreferences.getInstance();
      final last = DateTime.tryParse(prefs.getString(_refreshKey) ?? '');
      if (last != null &&
          DateTime.now().difference(last) < const Duration(hours: _refreshHours)) {
        return;
      }
      await _register();
      await prefs.setString(_refreshKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<void> _check() async {
    if (!_active || !mounted || _sheetOpen) return;
    try {
      final state = await pushPermissionState();
      if (state == 'granted') {
        await _refreshRegistrationIfDue();
        return;
      }
      if (state != 'denied' && state != 'not_granted') return;

      final prefs = await SharedPreferences.getInstance();
      final snoozed = DateTime.tryParse(prefs.getString(_snoozeKey) ?? '');
      if (snoozed != null &&
          DateTime.now().difference(snoozed) < const Duration(days: _snoozeDays)) {
        return;
      }
      if (!mounted) return;
      await _showSheet(prefs);
    } catch (_) {}
  }

  Future<void> _showSheet(SharedPreferences prefs) async {
    _sheetOpen = true;
    unawaited(AppErrorReporter.event(
      'PUSH_PROMPT_SHOWN',
      source: 'push_permission_prompt',
      screen: 'push',
    ));
    final open = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.notifications_active_outlined,
                  size: 44, color: Color(0xFF2563EB)),
              const SizedBox(height: 12),
              const Text(
                'Activa las notificaciones',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Así te avisamos cuando tu conductor llegue, cuando acepten tu '
                'viaje y de lo importante de tu cuenta. Sin ellas puedes perderte '
                'esos avisos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF667085), height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Abrir ajustes'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('Ahora no'),
              ),
            ],
          ),
        ),
      ),
    );
    _sheetOpen = false;
    if (open == true) {
      unawaited(AppErrorReporter.event(
        'PUSH_PROMPT_OPEN_SETTINGS',
        source: 'push_permission_prompt',
        screen: 'push',
      ));
      // Primero se intenta el aviso del sistema (solo aparece si Android aún
      // lo permite); si sigue bloqueado, se abren los ajustes de la app.
      await _register();
      final state = await pushPermissionState();
      if (state == 'granted') return;
      _awaitingSettings = true;
      await openAppSettings();
    } else {
      unawaited(AppErrorReporter.event(
        'PUSH_PROMPT_DISMISSED',
        source: 'push_permission_prompt',
        screen: 'push',
      ));
      await prefs.setString(_snoozeKey, DateTime.now().toIso8601String());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato: la sobreposición se sincroniza con el servidor y se pide al entrar,
/// y las llamadas nunca muestran ni marcan un número de teléfono.
void main() {
  late String sync;
  late String home;
  late String call;

  setUpAll(() {
    sync = File('lib/call_overlay_sync.dart').readAsStringSync();
    home = File('lib/video_style_home.dart').readAsStringSync();
    call = File('lib/private_voice_call.dart').readAsStringSync();
  });

  test('sync reads the real native permission and writes only when it changed', () {
    expect(sync, contains("invokeMethod<bool>('hasPermission')"));
    expect(sync, contains('if (stored == granted && storedInternet == granted) return granted;'));
    expect(sync, contains('internetCallsEnabled: granted,'));
    expect(sync, contains('sharePhoneForCalls: false,'));
    expect(sync, isNot(contains('share_phone_for_calls: true')));
  });

  test('overlay prompt is asked at startup and on resume and never mentions calls', () {
    expect(sync, contains('Future<void> promptOverlayIfNeeded('));
    expect(sync, contains('Es opcional. Si no la activas, tu viaje sigue normal.'));
    expect(sync, contains("'Sí, activar'"));
    expect(sync, contains("'No, ahora no'"));
    // «Sí» solo abre los ajustes del usuario; nunca lo manda directo sin preguntar.
    expect(sync, isNot(contains('openPermissionSettings\');\n  }\n}')));
    final prompt = sync.substring(sync.indexOf('Future<void> promptOverlayIfNeeded('));
    // Mensajes para el usuario: sin términos técnicos.
    expect(prompt, isNot(contains('ZEGO')));
    expect(prompt, isNot(contains('Android')));
    expect(prompt, isNot(contains('SYSTEM_ALERT')));
    expect(home, contains("import 'call_overlay_sync.dart';"));
    // Dos lugares: conductor al iniciar la app, y pasajero al empezar un viaje.
    // El bloque de arranque se repite en ambas pantallas; solo el del conductor pasa su guardia.
    // Conductor: al aceptar un viaje (una vez por viaje), no al iniciar la app.
    expect('promptOverlayIfNeeded(context, widget.service, driver: true)'.allMatches(home).length, 1);
    expect(home, contains('claimTripOverlayPrompt(tripId, driver: true)'));
    expect(home, isNot(contains('promptOverlayIfNeeded(context, widget.service, driver: true);\n      }')));
    expect(home, contains('await promptOverlayIfNeeded(context, widget.service);'));
    expect(home, contains('claimTripOverlayPrompt(tripId)'));
    expect(home, contains('if (widget is DriverMapHome) _maybePromptOverlayOnDriverTrip(next.activeTrip);'));
    expect(home, contains('void _maybePromptOverlayOnTripStart('));
  });

  test('driver state per push token: effective bar (permission AND option), wired on lifecycle', () {
    final sync = File('lib/call_overlay_sync.dart').readAsStringSync();
    expect(sync, contains('Future<void> syncDriverPushOverlayState('));
    expect(sync, contains('enabled: granted && barOn'));
    expect(sync, contains('DriverFloatingOfferSettings(accountId: service.userId)'));
    expect(home, contains('syncDriverPushOverlayState(widget.service)'));
    final service = File('lib/services/express_service.dart').readAsStringSync();
    expect(service, contains("'set_push_token_overlay_state'"));
  });

  test('push function decides per token with a fresh permission check, off by default', () {
    final fn = File('supabase/functions/express-push-dispatch/index.ts').readAsStringSync();
    expect(fn, contains('Deno.env.get("EXPRESS_OVERLAY_DATA_PUSH") === "on"'));
    expect(fn, contains('device.floating_offer_enabled === true'));
    expect(fn, contains('permission_checked_at'));
    expect(fn, isNot(contains('last_seen_at')));
    expect(fn, isNot(contains('user_call_preferences')));
  });

  test('ZEGO no longer asks for the overlay permission by itself', () {
    expect(call, isNot(contains('ZegoCallInvitationPermission.systemAlertWindow')));
    expect(call, contains('ZegoCallInvitationPermission.microphone'));
  });

  test('trip calls never open the dialer or show a phone number', () {
    // Envíos conserva marcar el número del destinatario que escribió el remitente;
    // aquí solo se fija la llamada entre pasajero y conductor.
    expect(call, isNot(contains("route['route'] == 'phone'")));
    expect(call, isNot(contains("route['phone']")));
    expect(call, contains('No pudimos contactar con'));
    expect(call, contains('Puedes escribirle por el chat del viaje.'));
    expect(call, contains('para que te mostremos las llamadas aunque tengas la app cerrada o en segundo plano.'));
  });
}

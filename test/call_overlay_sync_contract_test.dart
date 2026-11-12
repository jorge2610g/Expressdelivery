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
    expect(home, contains('_maybePromptOverlayOnDriverTrip(next.activeTrip);'));
    expect(home, contains('void _maybePromptOverlayOnTripStart('));
  });

  test('driver state per push token: effective bar (permission AND option), wired on lifecycle', () {
    final sync = File('lib/call_overlay_sync.dart').readAsStringSync();
    expect(sync, contains('Future<void> syncDriverPushOverlayState('));
    expect(sync, contains('final enabled = granted && barOn;'));
    expect(sync, contains('setPushTokenOverlayState(token: token, enabled: enabled)'));
    expect(sync, contains('DriverFloatingOfferSettings(accountId: service.userId)'));
    expect(home, contains('syncDriverPushOverlayState(widget.service)'));
    final service = File('lib/services/express_service.dart').readAsStringSync();
    expect(service, contains("'set_push_token_overlay_state'"));
  });

  test('native bar gets its action, confirms the drawn window and falls back to a normal notification', () {
    final receiver = File('android_overlay/kotlin/com/express/usuario1/ExpressMessagingService.kt')
        .readAsStringSync();
    final overlay = File('android_overlay/kotlin/com/express/usuario1/FloatingOfferService.kt')
        .readAsStringSync();
    expect(receiver, contains('.setAction(FloatingOfferService.ACTION_SHOW)'));
    expect(receiver, contains('postFallbackNotification(context, offerId'));
    expect(overlay, contains('drawnOfferId = id'));
    expect(overlay, contains('fallbackOrRefuse(intent, id)'));
    expect(overlay, contains('var drawnOfferId: String? = null'));
  });

  test('driver push state is throttled, confirmed by the server and cleared on sign-out', () {
    final sync = File('lib/call_overlay_sync.dart').readAsStringSync();
    expect(sync, contains('if (!confirmed) return;'));
    expect(sync, contains('clearDriverPushOverlayStateWith'));
    final mobile = File('lib/mobile_main.dart').readAsStringSync();
    expect(mobile, contains('await clearDriverPushOverlayStateWith();'));
    expect(home, contains('syncDriverPushOverlayState(widget.service, force: true)'));
  });

  test('push function selects overlay data-only per token with a fresh permission check', () {
    final fn = File('supabase/functions/express-push-dispatch/index.ts').readAsStringSync();
    expect(fn, contains('type === "ride_request"'));
    expect(fn, contains('device.floating_offer_enabled === true'));
    expect(fn, contains('permission_checked_at'));
    expect(fn, isNot(contains('last_seen_at')));
    expect(fn, isNot(contains('user_call_preferences')));
  });

  test('overlay data-only applies to opted-in devices in both runtime channels', () {
    final fn = File('supabase/functions/express-push-dispatch/index.ts').readAsStringSync();
    expect(fn, contains('device.floating_offer_enabled === true'));
    expect(fn, contains('hasFreshOverlayCheck(device.permission_checked_at)'));
    expect(fn, isNot(contains('EXPRESS_OVERLAY_ALLOWLIST')));
    expect(fn, isNot(contains('=== "preview" &&')));
    expect(fn, contains('...(dataOnly ? {} : { notification: { title, body } })'));
    expect(fn, contains('...(dataOnly ? {} : { notification: {'));
    expect(fn, contains('.select("id,token,platform,channel,floating_offer_enabled,permission_checked_at")'));
  });

  test('ZEGO no longer asks for the overlay permission by itself', () {
    expect(call, isNot(contains('ZegoCallInvitationPermission.systemAlertWindow')));
    expect(call, contains('ZegoCallInvitationPermission.microphone'));
  });

  test('driver menu always shows the floating offers entry so the bubble can be activated', () {
    // Sin permiso, la entrada sigue visible: su diálogo deshabilita el interruptor y
    // ofrece abrir los ajustes de Android. Ocultarla impedía activar la burbuja.
    final anchor = home.indexOf('leading: const Icon(Icons.layers_outlined)');
    expect(anchor, greaterThan(120));
    final beforeEntry = home.substring(anchor - 120, anchor);
    expect(beforeEntry, isNot(contains('if (overlayAllowed)')));
    expect(beforeEntry, contains('ListTile('));
    expect(home, contains('Primero autoriza el permiso de Android'));
  });

  test('opening Android settings never records an opt-in; only the explicit switch does', () {
    // Abrir Ajustes de Android no registra intención: el opt-in lo da solo el interruptor.
    expect(sync, isNot(contains('requestBubbleActivation')));
    expect(sync, isNot(contains('completeBubbleActivationAfterSettings')));
    expect(sync, isNot(contains('overlay_bubble_requested')));
    expect(sync, isNot(contains('enableBubbleOnceWhenGranted')));
    expect(home, isNot(contains('requestBubbleActivation')));
    expect(home, isNot(contains('completeBubbleActivationAfterSettings')));
    expect(home, contains('unawaited(syncDriverPushOverlayState(widget.service));'));
    expect(sync, contains('Future<void> setBubbleEnabledByDriver('));
  });

  test('trip calls offer the counterpart phone only through the trip RPC and the phone route', () {
    // Decisión del propietario: al llamar se muestra el número de la otra persona
    // (solo participantes del viaje activo) y se puede llamar por teléfono normal.
    // Con el interruptor de ZEGO apagado, el servidor responde route 'phone'.
    expect(call, contains("'trip_counterpart_phone'"));
    expect(call, contains("final zegoAvailable = route['route'] == 'internet';"));
    expect(call, contains('¿Quieres llamar a'));
    expect(call, isNot(contains('desactivadas')));
    expect(call, contains('Llamar por teléfono normal'));
    expect(call, contains('Puedes escribirle por el chat del viaje.'));
    expect(call, isNot(contains("route['phone']")));
  });
}

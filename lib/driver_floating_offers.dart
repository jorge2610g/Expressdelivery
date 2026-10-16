import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver_floating_offer_policy.dart';

/// Oferta que el conductor eligió desde la tarjeta flotante. La pantalla del
/// conductor la lee al volver a primer plano y abre su flujo existente para
/// esa oferta; la tarjeta nunca escribe en el servidor.
final ValueNotifier<String?> driverFloatingOfferFocus = ValueNotifier<String?>(null);

/// Oferta abierta desde el aviso de Android. Es independiente de la ventana
/// flotante: el ajuste del overlay no debe bloquear el detalle.
final ValueNotifier<String?> driverNotificationOfferFocus = ValueNotifier<String?>(null);

/// Ajuste voluntario del conductor: «Ventana flotante de ofertas». Nunca se
/// activa por defecto ni se solicita el permiso desde este módulo.
const String driverFloatingOfferSettingKey =
    'express_driver_floating_offer_enabled_v1';

class DriverFloatingOfferSettings {
  const DriverFloatingOfferSettings({this.accountId});
  // Do not transfer an opt-in permission preference between driver accounts.
  final String? accountId;
  String get _key => accountId == null || accountId!.isEmpty
      ? driverFloatingOfferSettingKey
      : '$driverFloatingOfferSettingKey:$accountId';

  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (_) {}
  }

  String get _dismissedKey => accountId == null || accountId!.isEmpty
      ? '$driverFloatingOfferSettingKey:bubble_dismissed_v1'
      : '$driverFloatingOfferSettingKey:bubble_dismissed_v1:$accountId';

  /// El conductor descartó la burbuja. Se respeta hasta que vuelva a abrir Express
  /// (nueva sesión) o reactive el ajuste.
  Future<bool> isBubbleDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_dismissedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBubbleDismissed(bool dismissed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dismissedKey, dismissed);
    } catch (_) {}
  }
}

/// Tarjeta que la ventana nativa muestra. Solo datos ya visibles para el
/// conductor en la app: no se inventan precios ni direcciones.
class FloatingOfferCard {
  const FloatingOfferCard({
    required this.offerId,
    required this.service,
    required this.priceLabel,
    required this.routeLabel,
    required this.expiresAt,
    this.displayDurationSeconds = 15,
  });

  final String offerId;
  final FloatingOfferService service;
  final String priceLabel;
  final String routeLabel;
  final DateTime expiresAt;

  /// Native display only. The server's offer expiry stays unchanged.
  final int displayDurationSeconds;

  Map<String, Object> toMap() => <String, Object>{
        'offerId': offerId,
        'service': service.name,
        'priceLabel': priceLabel,
        'routeLabel': routeLabel,
        'expiresAtMillis': expiresAt.millisecondsSinceEpoch,
        'displayDurationSeconds': displayDurationSeconds.clamp(10, 20).toInt(),
      };
}

/// Puente con la ventana nativa. Cualquier fallo del canal (plugin ausente,
/// Android sin permiso, error de plataforma) se trata como «no disponible»:
/// la app sigue con su notificación y su flujo interno.
class DriverFloatingOfferBridge {
  DriverFloatingOfferBridge({
    MethodChannel? channel,
    this.onAction,
    this.onBubbleEvent,
  }) : _channel = channel ?? const MethodChannel('express/floating_offers') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  /// Acción nativa: 'open' abre el detalle; nunca acepta la oferta.
  final void Function(String offerId, String action)? onAction;

  /// Eventos de la burbuja de acceso directo: 'open_app' o 'dismissed'.
  final void Function(String action)? onBubbleEvent;

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'bubbleEvent') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final action = args['action']?.toString() ?? '';
      if (action.isNotEmpty) onBubbleEvent?.call(action);
      return null;
    }
    if (call.method == 'action') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final offerId = args['offerId']?.toString() ?? '';
      final action = args['action']?.toString() ?? '';
      if (offerId.isNotEmpty && (action == 'open' || action == 'accept' || action == 'reject')) {
        applyFloatingOfferAction(offerId, action);
        onAction?.call(offerId, action);
      }
    }
    return null;
  }

  /// Recovers a user's tap if Android reopened Express with a fresh engine.
  /// It returns only the offer ID; DriverMapHome must verify that the current
  /// signed-in driver can still see the unexpired offer on their channel.
  Future<String?> consumePendingOpen() async {
    try {
      return await _channel.invokeMethod<String>('consumePendingOpen');
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre los ajustes oficiales de Android. No concede el permiso.
  Future<void> openPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openPermissionSettings');
    } catch (_) {}
  }

  Future<bool> show(FloatingOfferCard card) async {
    try {
      return await _channel.invokeMethod<bool>('show', card.toMap()) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }

  /// Muestra la burbuja circular. Devuelve false si Android no permite la ventana.
  Future<bool> showBubble() async {
    try {
      return await _channel.invokeMethod<bool>('bubbleShow') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> hideBubble() async {
    try {
      await _channel.invokeMethod<void>('bubbleHide');
    } catch (_) {}
  }

  /// Retira los avisos del sistema de nueva solicitud. Devuelve cuántos retiró.
  Future<int> retireOfferNotifications() async {
    try {
      return await _channel.invokeMethod<int>('cancelOfferNotifications') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}

/// Tocar el aviso solo devuelve el foco a la oferta. El flujo existente
/// valida la cuenta, el contexto de prueba, la vigencia y la autorización.
/// Conservamos 'accept' únicamente para compatibilidad con avisos antiguos.
void applyFloatingOfferAction(String offerId, String action) {
  if (action == 'open' || action == 'accept') {
    driverFloatingOfferFocus.value = offerId;
  }
}

/// Aplica la política: muestra la tarjeta solo si se cumplen todas las
/// condiciones, y la oculta en cuanto dejan de cumplirse.
class DriverFloatingOfferController {
  DriverFloatingOfferController({
    required this.bridge,
    required this.settings,
    this.onShown,
  });

  final DriverFloatingOfferBridge bridge;
  final DriverFloatingOfferSettings settings;

  /// Se llama solo cuando Android confirma la barra. Sirve para retirar el aviso
  /// del sistema de la misma oferta y no mostrar dos elementos.
  final void Function(String offerId)? onShown;

  String? _shownOfferId;
  String? _shownSignature;
  bool _bubbleShown = false;
  // True while a ride-offer system notification may still be visible.
  bool _offerNotificationPending = false;
  // Bumped only by close(). Syncs run one at a time (see sync), so a later sync
  // can no longer hide a native card that another sync just confirmed.
  int _closeEpoch = 0;
  Future<void> _queue = Future<void>.value();

  String? get shownOfferId => _shownOfferId;

  bool get bubbleShown => _bubbleShown;

  /// Burbuja: solo con Express en segundo plano, conductor en línea y disponible,
  /// ajuste y permiso activos, y no descartada en esta sesión. Es independiente de
  /// la tarjeta de ofertas.
  Future<void> _syncBubble({
    required bool wanted,
  }) async {
    if (wanted && !_bubbleShown) {
      _bubbleShown = await bridge.showBubble();
      debugPrint('[EXPRESS_DIAG] bubble_show_result=$_bubbleShown');
    } else if (!wanted && _bubbleShown) {
      await bridge.hideBubble();
      _bubbleShown = false;
    }
  }

  /// Syncs run one at a time. A sync that starts while a native show is in
  /// flight waits for it, so it cannot hide a card that was just confirmed.
  Future<void> sync({
    required FloatingOfferCard? offer,
    required bool driverOnline,
    required bool driverAvailable,
    required bool appInForeground,
    required DateTime now,
  }) {
    final run = _queue.then((_) => _syncOnce(
          offer: offer,
          driverOnline: driverOnline,
          driverAvailable: driverAvailable,
          appInForeground: appInForeground,
          now: now,
        ));
    _queue = run.catchError((Object _) {});
    return run;
  }

  Future<void> _syncOnce({
    required FloatingOfferCard? offer,
    required bool driverOnline,
    required bool driverAvailable,
    required bool appInForeground,
    required DateTime now,
  }) async {
    final epoch = _closeEpoch;
    final enabled = await settings.isEnabled();
    if (epoch != _closeEpoch) return;
    final granted = enabled && await bridge.hasPermission();
    if (epoch != _closeEpoch) return;
    final dismissed = await settings.isBubbleDismissed();
    if (epoch != _closeEpoch) return;
    debugPrint('[EXPRESS_DIAG] bubble_inputs enabled=$enabled granted=$granted online=$driverOnline avail=$driverAvailable fg=$appInForeground dismissed=$dismissed shown=$_bubbleShown');
    await _syncBubble(
      wanted: granted &&
          driverOnline &&
          driverAvailable &&
          !appInForeground &&
          !dismissed,
    );
    if (epoch != _closeEpoch) {
      // close() ran during the bubble call: the bubble must not stay visible.
      if (_bubbleShown) await _syncBubble(wanted: false);
      return;
    }
    if (offer != null) {
      _offerNotificationPending = true;
    } else if (_offerNotificationPending) {
      // Oferta vencida, aceptada o retirada: su aviso del sistema ya no sirve.
      await bridge.retireOfferNotifications();
      _offerNotificationPending = false;
    }
    final candidate = offer == null
        ? null
        : FloatingOfferCandidate(
            service: offer.service,
            expiresAt: offer.expiresAt,
          );
    final allowed = shouldShowFloatingOffer(
      FloatingOfferContext(
        settingEnabled: enabled,
        overlayPermissionGranted: granted,
        driverOnline: driverOnline,
        driverAvailable: driverAvailable,
        appInForeground: appInForeground,
        now: now,
      ),
      candidate,
    );

    if (allowed && offer != null) {
      final signature = '${offer.offerId}|${offer.priceLabel}|'
          '${offer.routeLabel}|${offer.expiresAt.millisecondsSinceEpoch}';
      if (_shownSignature == signature) return;
      final shown = await bridge.show(offer);
      // [EXPRESS_DIAG] temporal: resultado nativo de la tarjeta (ventana confirmada o no).
      debugPrint('[EXPRESS_DIAG] card_show offer=${offer.offerId} shown=$shown expiresInMs=${offer.expiresAt.difference(DateTime.now()).inMilliseconds}');
      if (epoch != _closeEpoch) {
        // close() ran while the native show was in flight.
        if (shown) await bridge.hide();
        return;
      }
      _shownOfferId = shown ? offer.offerId : null;
      _shownSignature = shown ? signature : null;
      if (shown) {
        // La tarjeta sustituye al aviso del sistema; no deben competir en pantalla.
        await bridge.retireOfferNotifications();
        onShown?.call(offer.offerId);
      }
    } else if (_shownOfferId != null) {
      await bridge.hide();
      _shownOfferId = null;
      _shownSignature = null;
    }
  }

  /// Cierra la tarjeta al aceptar, rechazar, expirar o cambiar el contexto.
  Future<void> close() async {
    ++_closeEpoch;
    _shownOfferId = null;
    _shownSignature = null;
    // Hide even if a native show is still in flight.
    await bridge.hide();
    // Express visible (or driver offline/disabled): the bubble must go too.
    await _syncBubble(wanted: false);
    if (_offerNotificationPending) {
      await bridge.retireOfferNotifications();
      _offerNotificationPending = false;
    }
  }
}

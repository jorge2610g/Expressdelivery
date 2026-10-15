import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver_floating_offer_policy.dart';

/// Oferta que el conductor eligió desde la tarjeta flotante. La pantalla del
/// conductor la lee al volver a primer plano y abre su flujo existente para
/// esa oferta; la tarjeta nunca escribe en el servidor.
final ValueNotifier<String?> driverFloatingOfferFocus = ValueNotifier<String?>(null);

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
  });

  final String offerId;
  final FloatingOfferService service;
  final String priceLabel;
  final String routeLabel;
  final DateTime expiresAt;

  Map<String, Object> toMap() => <String, Object>{
        'offerId': offerId,
        'service': service.name,
        'priceLabel': priceLabel,
        'routeLabel': routeLabel,
        'expiresAtMillis': expiresAt.millisecondsSinceEpoch,
      };
}

/// Puente con la ventana nativa. Cualquier fallo del canal (plugin ausente,
/// Android sin permiso, error de plataforma) se trata como «no disponible»:
/// la app sigue con su notificación y su flujo interno.
class DriverFloatingOfferBridge {
  DriverFloatingOfferBridge({
    MethodChannel? channel,
    this.onAction,
  }) : _channel = channel ?? const MethodChannel('express/floating_offers') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  /// Acción nativa: 'open' abre el detalle; nunca acepta la oferta.
  final void Function(String offerId, String action)? onAction;

  Future<dynamic> _handle(MethodCall call) async {
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
  });

  final DriverFloatingOfferBridge bridge;
  final DriverFloatingOfferSettings settings;

  String? _shownOfferId;
  String? _shownSignature;
  int _revision = 0;

  String? get shownOfferId => _shownOfferId;

  Future<void> sync({
    required FloatingOfferCard? offer,
    required bool driverOnline,
    required bool driverAvailable,
    required bool appInForeground,
    required DateTime now,
  }) async {
    final revision = ++_revision;
    final enabled = await settings.isEnabled();
    if (revision != _revision) return;
    final granted = enabled && await bridge.hasPermission();
    if (revision != _revision) return;
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
      if (revision != _revision) {
        // Lifecycle change superseded the in-flight native show.
        if (shown) await bridge.hide();
        return;
      }
      _shownOfferId = shown ? offer.offerId : null;
      _shownSignature = shown ? signature : null;
    } else if (_shownOfferId != null) {
      await bridge.hide();
      _shownOfferId = null;
      _shownSignature = null;
    }
  }

  /// Cierra la tarjeta al aceptar, rechazar, expirar o cambiar el contexto.
  Future<void> close() async {
    ++_revision;
    _shownOfferId = null;
    _shownSignature = null;
    // Hide even if a native show is still in flight.
    await bridge.hide();
  }
}

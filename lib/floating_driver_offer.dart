import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screen_overlay/flutter_screen_overlay.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';

const _floatingPreferencePrefix = 'express.driver_floating_offer_enabled.';
const _floatingPendingAcceptPrefix = 'express.driver_floating_offer_pending_accept.';

class ExpressFloatingOfferPreferenceState {
  const ExpressFloatingOfferPreferenceState({
    required this.driverEnabled,
    required this.adminAllowed,
    required this.permissionGranted,
    required this.channel,
  });

  final bool driverEnabled;
  final bool adminAllowed;
  final bool permissionGranted;
  final String channel;

  bool get effective =>
      driverEnabled && adminAllowed && permissionGranted;
}

class ExpressFloatingDriverOfferController {
  ExpressFloatingDriverOfferController._();

  static StreamSubscription<dynamic>? _overlaySubscription;
  static Completer<void>? _overlayReadyCompleter;
  static String? _pendingAcceptRideId;

  static String? get pendingAcceptRideId => _pendingAcceptRideId;

  static Future<String> _packageName() async =>
      (await PackageInfo.fromPlatform()).packageName;

  static Future<String> _runtimeChannel([
    Map<String, dynamic>? data,
  ]) async {
    final explicit = data?['channel']?.toString().trim().toLowerCase();
    if (explicit == 'preview' || explicit == 'production') {
      return explicit!;
    }
    final packageName = await _packageName();
    return packageName.endsWith('.preview') ? 'preview' : 'production';
  }

  static Future<String> _preferenceKey() async =>
      _floatingPreferencePrefix + await _packageName();

  static Future<String> _pendingAcceptKey() async =>
      _floatingPendingAcceptPrefix + await _packageName();

  static Future<bool> _driverEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(await _preferenceKey()) ?? false;
  }

  static Future<void> _saveDriverEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _preferenceKey(), value);
  }

  static Future<void> _savePendingAccept(String rideRequestId) async {
    _pendingAcceptRideId = rideRequestId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _pendingAcceptKey(), rideRequestId);
  }

  static Future<void> clearPendingAcceptRideId() async {
    _pendingAcceptRideId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _pendingAcceptKey());
  }

  static Future<bool> _adminAllowed(String channel) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '$supabaseUrl/rest/v1/rpc/driver_floating_offer_config',
            ),
            headers: {
              'apikey': supabasePublishableKey,
              'Authorization': 'Bearer $supabasePublishableKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'p_channel': channel}),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is bool) return decoded;
      if (decoded is Map) return decoded['enabled'] == true;
      return decoded?.toString().toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<ExpressFloatingOfferPreferenceState> preferenceState({
    String? channel,
  }) async {
    if (!Platform.isAndroid) {
      return ExpressFloatingOfferPreferenceState(
        driverEnabled: false,
        adminAllowed: false,
        permissionGranted: false,
        channel: channel ?? ExpressRuntimeChannel.name,
      );
    }
    final resolvedChannel = channel ?? ExpressRuntimeChannel.name;
    final results = await Future.wait<Object>([
      _driverEnabled(),
      _adminAllowed(resolvedChannel),
      FlutterScreenOverlay.isPermissionGranted(),
    ]);
    return ExpressFloatingOfferPreferenceState(
      driverEnabled: results[0] == true,
      adminAllowed: results[1] == true,
      permissionGranted: results[2] == true,
      channel: resolvedChannel,
    );
  }

  static Future<ExpressFloatingOfferPreferenceState> setDriverEnabled(
    bool enabled, {
    String? channel,
  }) async {
    final resolvedChannel = channel ?? ExpressRuntimeChannel.name;
    if (!Platform.isAndroid) {
      return preferenceState(channel: resolvedChannel);
    }

    if (!enabled) {
      await _saveDriverEnabled(false);
      if (await FlutterScreenOverlay.isActive()) {
        await FlutterScreenOverlay.closeOverlay();
      }
      return preferenceState(channel: resolvedChannel);
    }

    final allowed = await _adminAllowed(resolvedChannel);
    if (!allowed) {
      await _saveDriverEnabled(false);
      return preferenceState(channel: resolvedChannel);
    }

    var permission = await FlutterScreenOverlay.isPermissionGranted();
    if (!permission) {
      permission = await FlutterScreenOverlay.requestPermission() == true;
    }
    if (permission) {
      try {
        await FlutterScreenOverlay.warmUp();
      } catch (_) {}
    }
    await _saveDriverEnabled(permission);
    return preferenceState(channel: resolvedChannel);
  }

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    _pendingAcceptRideId = prefs.getString(await _pendingAcceptKey());

    if (await _driverEnabled() &&
        await FlutterScreenOverlay.isPermissionGranted()) {
      try {
        await FlutterScreenOverlay.warmUp();
      } catch (_) {}
    }

    _overlaySubscription ??=
        FlutterScreenOverlay.overlayListener.listen((event) {
      final payload = _decodeMap(event);
      if (payload?['source'] != 'express_floating_offer') return;
      if (payload?['action'] == 'ready') {
        final completer = _overlayReadyCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
        return;
      }
      if (payload?['action'] != 'accept') return;
      final rideRequestId =
          payload?['ride_request_id']?.toString().trim() ?? '';
      if (rideRequestId.isEmpty) return;
      unawaited(_savePendingAccept(rideRequestId));
    });
  }

  static Future<void> handleBackgroundPush({
    required Map<String, dynamic> data,
    String? title,
    String? body,
  }) async {
    if (!Platform.isAndroid) return;

    final type = data['type']?.toString().trim().toLowerCase() ??
        data['event_type']?.toString().trim().toLowerCase() ??
        '';
    final mode = data['mode']?.toString().trim().toLowerCase();
    if (type != 'ride_request' && mode != 'driver') return;

    if (!await _driverEnabled()) return;
    final channel = await _runtimeChannel(data);
    if (!await _adminAllowed(channel)) return;
    if (!await FlutterScreenOverlay.isPermissionGranted()) return;

    try {
      await FlutterScreenOverlay.warmUp();
    } catch (_) {}

    final rideRequestId =
        data['ride_request_id']?.toString().trim() ??
            data['request_id']?.toString().trim() ??
            '';
    if (rideRequestId.isEmpty) return;

    final timeout = int.tryParse(
          data['offer_timeout_seconds']?.toString() ??
              data['timeout_seconds']?.toString() ??
              '',
        ) ??
        30;
    final payload = <String, dynamic>{
      ...data,
      'source': 'express_floating_offer',
      'kind': 'offer',
      'channel': channel,
      'ride_request_id': rideRequestId,
      'title': (title == null || title.trim().isEmpty)
          ? 'Nueva solicitud Express'
          : title.trim(),
      'body': (body == null || body.trim().isEmpty)
          ? 'Tienes una solicitud cercana disponible.'
          : body.trim(),
      'expires_at': DateTime.now()
          .add(Duration(seconds: timeout.clamp(10, 180).toInt()))
          .toUtc()
          .toIso8601String(),
    };

    if (await FlutterScreenOverlay.isActive()) {
      await FlutterScreenOverlay.closeOverlay();
    }

    // The overlay owns a separate Flutter engine/isolate. Wait until that
    // isolate confirms its listener is attached instead of guessing with a
    // fixed delay; otherwise the first offer can be lost on slower OEMs.
    _overlayReadyCompleter = Completer<void>();
    await FlutterScreenOverlay.showOverlay(
      height: 330,
      width: WindowSize.matchParent,
      alignment: OverlayAlignment.topCenter,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: 'Express · nueva oferta',
      overlayContent: 'Toca para aceptar o rechazar',
      enableDrag: true,
      positionGravity: PositionGravity.auto,
    );

    try {
      await _overlayReadyCompleter!.future.timeout(
        const Duration(seconds: 4),
      );
    } catch (_) {
      // Keep a compatibility fallback: send even if the vendor delays the
      // overlay-to-main ready event.
    } finally {
      _overlayReadyCompleter = null;
    }

    final encodedPayload = jsonEncode(payload);
    for (var attempt = 0; attempt < 3; attempt++) {
      await FlutterScreenOverlay.shareData(encodedPayload);
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    }
  }

  static Map<String, dynamic>? _decodeMap(dynamic event) {
    try {
      final decoded =
          event is String ? jsonDecode(event) : event;
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }
}

void runExpressFloatingOfferOverlay() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ExpressFloatingOfferApp());
}

class _ExpressFloatingOfferApp extends StatelessWidget {
  const _ExpressFloatingOfferApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _ExpressFloatingOfferView(),
    );
  }
}

class _ExpressFloatingOfferView extends StatefulWidget {
  const _ExpressFloatingOfferView();

  @override
  State<_ExpressFloatingOfferView> createState() =>
      _ExpressFloatingOfferViewState();
}

class _ExpressFloatingOfferViewState
    extends State<_ExpressFloatingOfferView> {
  StreamSubscription<dynamic>? _subscription;
  Timer? _ticker;
  Map<String, dynamic>? _payload;
  int _remaining = 30;

  @override
  void initState() {
    super.initState();
    _subscription = FlutterScreenOverlay.overlayListener.listen((event) {
      final decoded = ExpressFloatingDriverOfferController._decodeMap(event);
      if (decoded?['source'] != 'express_floating_offer' ||
          decoded?['kind'] != 'offer') {
        return;
      }
      _applyPayload(decoded!);
    });
    unawaited(
      FlutterScreenOverlay.shareData(
        jsonEncode({
          'source': 'express_floating_offer',
          'action': 'ready',
        }),
      ),
    );
  }

  void _applyPayload(Map<String, dynamic> payload) {
    _ticker?.cancel();
    final expiresAt =
        DateTime.tryParse(payload['expires_at']?.toString() ?? '');
    if (!mounted) return;
    setState(() {
      _payload = payload;
      _remaining = expiresAt == null
          ? 30
          : expiresAt.difference(DateTime.now().toUtc()).inSeconds.clamp(0, 180).toInt();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      final next = _remaining - 1;
      if (next <= 0) {
        _ticker?.cancel();
        await FlutterScreenOverlay.closeOverlay();
        return;
      }
      setState(() => _remaining = next);
    });
  }

  Future<void> _respond(String action) async {
    final payload = _payload;
    if (payload == null) return;
    final rideRequestId =
        payload['ride_request_id']?.toString().trim() ?? '';
    if (rideRequestId.isEmpty) {
      await FlutterScreenOverlay.closeOverlay();
      return;
    }

    await FlutterScreenOverlay.shareData(jsonEncode({
      'source': 'express_floating_offer',
      'action': action,
      'ride_request_id': rideRequestId,
      'channel': payload['channel']?.toString() ?? 'production',
    }));

    if (action == 'accept') {
      await ExpressFloatingDriverOfferController._savePendingAccept(
        rideRequestId,
      );
      try {
        final packageName =
            (await PackageInfo.fromPlatform()).packageName;
        final uri = Uri(
          scheme: packageName,
          host: 'login-callback',
          queryParameters: {
            'floating_offer': 'accept',
            'ride_request_id': rideRequestId,
          },
        );
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    await FlutterScreenOverlay.closeOverlay();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final title = payload?['title']?.toString() ??
        'Preparando oferta Express…';
    final body = payload?['body']?.toString() ??
        'Conectando con la solicitud. Un momento…';
    final pickup = payload?['pickup_address']?.toString().trim() ?? '';
    final destination =
        payload?['destination_address']?.toString().trim() ?? '';

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFDFDFD),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFF0B57D0),
                      child: Icon(
                        Icons.local_taxi_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Oferta disponible · $_remaining s',
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.25),
                ),
                if (pickup.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Origen: $pickup',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                if (destination.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Destino: $destination',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: payload == null
                            ? null
                            : () => _respond('reject'),
                        child: const Text('Rechazar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: payload == null
                            ? null
                            : () => _respond('accept'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0B57D0),
                        ),
                        child: const Text('Aceptar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

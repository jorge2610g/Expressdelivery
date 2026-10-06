import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'services/express_service.dart';

class ExpressPrivateVoiceCall {
  ExpressPrivateVoiceCall._();

  static final ExpressPrivateVoiceCall instance = ExpressPrivateVoiceCall._();

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialized = false;
  String? _initializedSupabaseUserId;
  int? _appID;
  String? _zegoUserID;
  String? _zegoUserName;
  Timer? _tokenRefreshTimer;
  Future<void>? _syncing;

  bool get initialized => _initialized;

  void attachNavigator(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final response = await supabase.functions.invoke(
      'zego-call',
      body: <String, dynamic>{
        ...body,
        'channel': ExpressRuntimeChannel.name,
      },
    );
    final data = response.data;
    if (data is! Map) {
      throw StateError('El servicio de llamadas devolvió una respuesta inválida.');
    }
    final result = Map<String, dynamic>.from(data);
    if (result['ok'] == false) {
      final message = result['message']?.toString().trim();
      throw StateError(
        message == null || message.isEmpty
            ? 'No se pudo preparar la llamada privada.'
            : message,
      );
    }
    return result;
  }

  Future<void> syncForSession() {
    final pending = _syncing;
    if (pending != null) return pending;
    final completer = Completer<void>();
    _syncing = completer.future;
    () async {
      try {
        final session = supabase.auth.currentSession;
        if (session == null) {
          await uninitialize();
          return;
        }

        final result = await _invoke(const {'action': 'bootstrap'});
        final configured = result['configured'] == true;
        final appID = int.tryParse(result['appID']?.toString() ?? '');
        final token = result['token']?.toString() ?? '';
        final userID = result['userID']?.toString() ?? '';
        final userName = result['userName']?.toString() ?? 'Express';

        if (!configured ||
            appID == null ||
            token.isEmpty ||
            userID.isEmpty) {
          await uninitialize();
          return;
        }

        if (_initialized &&
            _initializedSupabaseUserId == session.user.id &&
            _appID == appID &&
            _zegoUserID == userID) {
          await ZegoUIKitPrebuiltCallController().room.renewToken(token);
          _scheduleTokenRefresh(result);
          return;
        }

        await uninitialize();

        final navigatorKey = _navigatorKey;
        if (navigatorKey != null) {
          ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);
        }

        await ZegoUIKitPrebuiltCallInvitationService().init(
          appID: appID,
          token: token,
          userID: userID,
          userName: userName,
          plugins: [ZegoUIKitSignalingPlugin()],
        );

        _initialized = true;
        _initializedSupabaseUserId = session.user.id;
        _appID = appID;
        _zegoUserID = userID;
        _zegoUserName = userName;
        _scheduleTokenRefresh(result);
      } catch (_) {
        // Calls are additive. A provider/configuration problem must never block
        // the main Express ride experience.
        await uninitialize();
      } finally {
        completer.complete();
        _syncing = null;
      }
    }();
    return completer.future;
  }

  void _scheduleTokenRefresh(Map<String, dynamic> result) {
    _tokenRefreshTimer?.cancel();
    final ttl = int.tryParse(result['tokenExpiresInSeconds']?.toString() ?? '') ??
        6 * 60 * 60;
    final refreshAfter = Duration(
      seconds: ttl > 600 ? ttl - 300 : (ttl * 0.8).round(),
    );
    _tokenRefreshTimer = Timer(refreshAfter, () {
      unawaited(syncForSession());
    });
  }

  Future<void> uninitialize() async {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    if (_initialized || ZegoUIKitPrebuiltCallInvitationService().isInit) {
      try {
        await ZegoUIKitPrebuiltCallInvitationService().uninit();
      } catch (_) {}
    }
    _initialized = false;
    _initializedSupabaseUserId = null;
    _appID = null;
    _zegoUserID = null;
    _zegoUserName = null;
  }

  Future<void> startTripCall({
    required BuildContext context,
    required ExpressService service,
    required Map<String, dynamic> trip,
  }) async {
    final tripID = trip['id']?.toString() ?? '';
    if (tripID.isEmpty) {
      _message(context, 'No encontramos el viaje para iniciar la llamada.');
      return;
    }

    try {
      await syncForSession();
      final result = await _invoke({
        'action': 'prepare',
        'tripId': tripID,
      });

      final appID = int.tryParse(result['appID']?.toString() ?? '');
      final token = result['token']?.toString() ?? '';
      final userID = result['userID']?.toString() ?? '';
      final userName = result['userName']?.toString() ?? 'Express';
      final peerUserID = result['peerUserID']?.toString() ?? '';
      final peerUserName =
          result['peerUserName']?.toString() ?? 'Usuario Express';
      final callID = result['callID']?.toString() ?? '';
      final callLogID = result['callLogID']?.toString() ?? '';
      final resourceID = result['resourceID']?.toString().trim();
      final timeoutSeconds =
          int.tryParse(result['inviteTimeoutSeconds']?.toString() ?? '') ?? 30;

      if (appID == null ||
          token.isEmpty ||
          userID.isEmpty ||
          peerUserID.isEmpty ||
          callID.isEmpty) {
        throw StateError('La sesión privada de llamada está incompleta.');
      }

      if (!_initialized ||
          _appID != appID ||
          _zegoUserID != userID ||
          _initializedSupabaseUserId != service.userId) {
        await uninitialize();
        final navigatorKey = _navigatorKey;
        if (navigatorKey != null) {
          ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);
        }
        await ZegoUIKitPrebuiltCallInvitationService().init(
          appID: appID,
          token: token,
          userID: userID,
          userName: userName,
          plugins: [ZegoUIKitSignalingPlugin()],
        );
        _initialized = true;
        _initializedSupabaseUserId = service.userId;
        _appID = appID;
        _zegoUserID = userID;
        _zegoUserName = userName;
        _scheduleTokenRefresh(result);
      } else {
        await ZegoUIKitPrebuiltCallController().room.renewToken(token);
      }

      final sent = await ZegoUIKitPrebuiltCallInvitationService().send(
        invitees: [ZegoCallUser(peerUserID, peerUserName)],
        isVideoCall: false,
        callID: callID,
        resourceID:
            resourceID == null || resourceID.isEmpty ? null : resourceID,
        timeoutSeconds: timeoutSeconds,
        notificationTitle: 'Llamada de Express',
        notificationMessage: '$peerUserName tiene una llamada de tu viaje.',
        customData: jsonEncode({
          'trip_id': tripID,
          'call_log_id': callLogID,
          'privacy': 'phone_numbers_hidden',
        }),
      );

      if (!sent) {
        if (callLogID.isNotEmpty) {
          unawaited(
            _invoke({
              'action': 'event',
              'callLogID': callLogID,
              'event': 'failed',
            }).catchError((_) => <String, dynamic>{}),
          );
        }
        throw StateError('No se pudo enviar la invitación de llamada.');
      }

      if (!context.mounted) return;
      _message(
        context,
        'Llamando por Express. Tu número de teléfono permanece privado.',
      );
    } catch (error) {
      if (!context.mounted) return;
      final raw = error.toString().replaceFirst('Bad state: ', '');
      _message(
        context,
        raw.isEmpty ? 'No se pudo iniciar la llamada privada.' : raw,
      );
    }
  }

  void _message(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }
}

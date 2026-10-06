import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import 'app_error_reporter.dart';
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
  final ZegoUIKitSignalingPlugin _signalingPlugin =
      ZegoUIKitSignalingPlugin();
  bool _systemCallingUiReady = false;
  // Preview +155: call-start feedback is Dart-only and safe for Shorebird OTA.
  bool _startingTripCall = false;
  OverlayEntry? _connectingCallOverlay;

  bool get initialized => _initialized;

  void attachNavigator(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);
  }

  Future<void> prepareSystemCallingUI() async {
    if (_systemCallingUiReady) return;
    final navigatorKey = _navigatorKey;
    if (navigatorKey == null) {
      await AppErrorReporter.warning(
        'ZEGO system calling UI skipped: navigator key missing',
        source: 'private_voice_call',
        eventName: 'zego_system_calling_ui_missing_navigator',
      );
      return;
    }

    try {
      final invitationService = ZegoUIKitPrebuiltCallInvitationService();
      invitationService.setNavigatorKey(navigatorKey);
      await invitationService.useSystemCallingUI([_signalingPlugin]);
      _systemCallingUiReady = true;
      await AppErrorReporter.event(
        'zego_system_calling_ui_ready',
        source: 'private_voice_call',
        message: 'ZEGOCLOUD system calling UI registered',
      );
    } catch (error, stack) {
      await AppErrorReporter.capture(
        error,
        stack,
        source: 'private_voice_call',
        eventName: 'zego_system_calling_ui_failed',
        fatal: false,
      );
    }
  }

  ZegoUIKitPrebuiltCallInvitationEvents get _invitationEvents =>
      ZegoUIKitPrebuiltCallInvitationEvents(
        onError: (error) {
          unawaited(
            AppErrorReporter.capture(
              StateError('ZEGOCLOUD invitation error: $error'),
              StackTrace.current,
              source: 'private_voice_call',
              eventName: 'zego_invitation_error',
              fatal: false,
            ),
          );
        },
        onOutgoingCallSent: (
          callID,
          caller,
          callType,
          callees,
          customData,
        ) {
          unawaited(
            AppErrorReporter.event(
              'zego_outgoing_call_sent',
              source: 'private_voice_call',
              message: 'ZEGOCLOUD accepted outgoing invitation',
              context: {
                'call_id': callID,
                'callee_count': callees.length,
                'call_type': callType.toString(),
              },
            ),
          );
        },
        onIncomingCallReceived: (
          callID,
          caller,
          callType,
          callees,
          customData,
        ) {
          unawaited(
            AppErrorReporter.event(
              'zego_incoming_call_received',
              source: 'private_voice_call',
              message: 'ZEGOCLOUD incoming invitation received',
              context: {
                'call_id': callID,
                'callee_count': callees.length,
                'call_type': callType.toString(),
              },
            ),
          );
        },
      );

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

  ZegoUIKitPrebuiltCallConfig _voiceCallConfig(
    ZegoCallInvitationData invitationData,
  ) {
    final config = ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();
    config.turnOnCameraWhenJoining = false;
    config.turnOnMicrophoneWhenJoining = true;
    config.useSpeakerWhenJoining = false;
    config.audioVideoView = ZegoCallAudioVideoViewConfig(
      showCameraStateOnView: false,
      showMicrophoneStateOnView: false,
      showUserNameOnView: true,
      showAvatarInAudioMode: true,
      showSoundWavesInAudioMode: false,
      showWaitingCallAcceptAudioVideoView: false,
      showLocalUser: false,
      showOnlyCameraMicrophoneOpened: false,
    );
    config.topMenuBar = ZegoCallTopMenuBarConfig(
      isVisible: false,
      buttons: const <ZegoCallMenuBarButtonName>[],
    );
    config.bottomMenuBar = ZegoCallBottomMenuBarConfig(
      isVisible: true,
      hideAutomatically: false,
      hideByClick: false,
      maxCount: 3,
      buttons: const <ZegoCallMenuBarButtonName>[
        ZegoCallMenuBarButtonName.toggleMicrophoneButton,
        ZegoCallMenuBarButtonName.switchAudioOutputButton,
        ZegoCallMenuBarButtonName.hangUpButton,
      ],
    );
    config.duration = ZegoCallDurationConfig(isVisible: true);
    return config;
  }

  ZegoCallInvitationInnerText _spanishInvitationText() =>
      ZegoCallInvitationInnerText(
        incomingVoiceCallDialogTitle: 'Llamada de Express',
        incomingVoiceCallDialogMessage: '%0 te está llamando',
        incomingVoiceCallPageTitle: '%0',
        incomingVoiceCallPageMessage: 'Llamada de voz de tu viaje',
        incomingCallPageDeclineButton: 'Rechazar',
        incomingCallPageAcceptButton: 'Aceptar',
        outgoingCallPageACancelButton: 'Cancelar',
        outgoingVoiceCallPageMessage: 'Llamando…',
        permissionConfirmDialogTitle: 'Permiso de micrófono',
        permissionConfirmDialogAllowButton: 'Permitir',
        permissionConfirmDialogDenyButton: 'No permitir',
        permissionConfirmDialogCancelButton: 'Cancelar',
        permissionConfirmDialogOKButton: 'Aceptar',
        callingToolbarMicrophoneButtonText: 'Micrófono',
        callingToolbarMicrophoneOnButtonText: 'Micrófono',
        callingToolbarMicrophoneOffButtonText: 'Micrófono apagado',
        callingToolbarSpeakerButtonText: 'Altavoz',
        callingToolbarSpeakerOnButtonText: 'Altavoz',
        callingToolbarSpeakerOffButtonText: 'Auricular',
      );

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

        await prepareSystemCallingUI();
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
          plugins: [_signalingPlugin],
          config: ZegoCallInvitationConfig(
            permissions: const <ZegoCallInvitationPermission>[
              ZegoCallInvitationPermission.microphone,
            ],
          ),
          requireConfig: _voiceCallConfig,
          innerText: _spanishInvitationText(),
          invitationEvents: _invitationEvents,
        );

        _initialized = true;
        _initializedSupabaseUserId = session.user.id;
        _appID = appID;
        _zegoUserID = userID;
        _zegoUserName = userName;
        _scheduleTokenRefresh(result);
      } catch (error, stack) {
        // Calls are additive. A provider/configuration problem must never block
        // the main Express ride experience.
        await AppErrorReporter.capture(
          error,
          stack,
          source: 'private_voice_call',
          eventName: 'zego_session_sync_failed',
          fatal: false,
        );
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

  void _showConnectingCallOverlay(BuildContext context) {
    _hideConnectingCallOverlay();
    if (!context.mounted) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (_) => const _ExpressCallConnectingOverlay(),
    );
    _connectingCallOverlay = entry;
    overlay.insert(entry);
  }

  void _hideConnectingCallOverlay() {
    final entry = _connectingCallOverlay;
    _connectingCallOverlay = null;
    try {
      entry?.remove();
    } catch (_) {}
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

    if (_startingTripCall) return;
    _startingTripCall = true;
    _showConnectingCallOverlay(context);
    unawaited(
      AppErrorReporter.event(
        'zego_call_connecting_ui_shown',
        source: 'private_voice_call',
        message: 'Private call connecting feedback shown',
        context: {'trip_id': tripID},
      ),
    );

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
          plugins: [_signalingPlugin],
          config: ZegoCallInvitationConfig(
            permissions: const <ZegoCallInvitationPermission>[
              ZegoCallInvitationPermission.microphone,
            ],
          ),
          requireConfig: _voiceCallConfig,
          innerText: _spanishInvitationText(),
          invitationEvents: _invitationEvents,
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

      final signalingState = _signalingPlugin.getConnectionState().toString();
      unawaited(
        AppErrorReporter.event(
          'zego_invitation_send_attempt',
          source: 'private_voice_call',
          message: 'Sending ZEGOCLOUD trip invitation',
          context: {
            'call_id': callID,
            'signaling_state': signalingState,
            'system_calling_ui_ready': _systemCallingUiReady,
            'service_initialized': _initialized,
            'resource_id_configured':
                resourceID != null && resourceID.isNotEmpty,
          },
        ),
      );

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
        unawaited(
          AppErrorReporter.warning(
            'ZEGOCLOUD send() returned false',
            source: 'private_voice_call',
            eventName: 'zego_invitation_send_failed',
            context: {
              'call_id': callID,
              'signaling_state': signalingState,
              'system_calling_ui_ready': _systemCallingUiReady,
              'service_initialized': _initialized,
              'resource_id_configured':
                  resourceID != null && resourceID.isNotEmpty,
            },
          ),
        );
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

      unawaited(
        AppErrorReporter.event(
          'zego_invitation_send_success',
          source: 'private_voice_call',
          message: 'ZEGOCLOUD trip invitation sent',
          context: {
            'call_id': callID,
            'signaling_state': signalingState,
          },
        ),
      );

      _hideConnectingCallOverlay();
      _startingTripCall = false;
      if (!context.mounted) return;
      _message(
        context,
        'Llamando por Express. Tu número de teléfono permanece privado.',
      );
    } catch (error, stack) {
      _hideConnectingCallOverlay();
      _startingTripCall = false;
      unawaited(
        AppErrorReporter.capture(
          error,
          stack,
          source: 'private_voice_call',
          eventName: 'zego_trip_call_failed',
          fatal: false,
          context: {'trip_id': tripID},
        ),
      );
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


class _ExpressCallConnectingOverlay extends StatefulWidget {
  const _ExpressCallConnectingOverlay();

  @override
  State<_ExpressCallConnectingOverlay> createState() =>
      _ExpressCallConnectingOverlayState();
}

class _ExpressCallConnectingOverlayState
    extends State<_ExpressCallConnectingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: .92, end: 1.08).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: .38),
        child: SafeArea(
          child: Center(
            child: Container(
              width: 290,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 78,
                        height: 78,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      ScaleTransition(
                        scale: _pulse,
                        child: CircleAvatar(
                          radius: 27,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: const Icon(
                            Icons.call_rounded,
                            color: Colors.white,
                            size: 29,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Conectando llamada…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Estamos conectando de forma privada con la otra persona.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Puede tardar unos segundos',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

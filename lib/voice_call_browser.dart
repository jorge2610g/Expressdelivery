import 'dart:js_interop';

@JS('expressWebVoiceInit')
external JSPromise<JSBoolean> _initializeVoice(
    JSNumber appID, JSString token, JSString userID, JSString userName);

@JS('expressWebVoiceSend')
external JSPromise<JSBoolean> _sendVoice(JSString callID,
    JSString peerUserID, JSString peerUserName,
    JSNumber timeout, JSString resourceID);

@JS('expressWebVoiceRelease')
external JSBoolean _releaseVoice();

/// The JavaScript Web Call Kit uses the same signed server Token04
/// and 32-character identity as the native Flutter SDK.
Future<bool> initializeExpressBrowserVoice({
  required int appID,
  required String token,
  required String userID,
  required String userName,
}) async {
  final value = await _initializeVoice(
      appID.toJS, token.toJS, userID.toJS, userName.toJS).toDart;
  return value.toDart;
}

Future<bool> sendExpressBrowserVoice({
  required String callID,
  required String peerUserID,
  required String peerUserName,
  required int timeoutSeconds,
  required String resourceID,
}) async {
  final value = await _sendVoice(callID.toJS, peerUserID.toJS,
      peerUserName.toJS, timeoutSeconds.toJS, resourceID.toJS).toDart;
  return value.toDart;
}

void releaseExpressBrowserVoice() => _releaseVoice();

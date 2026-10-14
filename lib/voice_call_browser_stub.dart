/// Android/iOS preserve the existing native ZEGOCLOUD implementation.
Future<bool> initializeExpressBrowserVoice({
  required int appID,
  required String token,
  required String userID,
  required String userName,
}) async => false;

Future<bool> sendExpressBrowserVoice({
  required String callID,
  required String peerUserID,
  required String peerUserName,
  required int timeoutSeconds,
  required String resourceID,
}) async => false;

void releaseExpressBrowserVoice() {}

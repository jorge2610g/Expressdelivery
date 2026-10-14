/**
 * Browser-specific ZEGOCLOUD Call Kit. The Flutter prebuilt Call Kit used by
 * Android/iOS does NOT support Flutter Web. Never call native Flutter ZEGO
 * plugin methods from here.
 *
 * Only the Supabase Edge Function 'zego-call' supplies a signed Token04.
 * This script never receives or contains ZEGO_SERVER_SECRET.
 *
 * IMPORTANT: Canary/testing only until web↔web and web↔Android invitation
 * interoperability has been verified using two different user accounts.
 */
(function () {
  'use strict';
  const ZIM_URL =
      'https://unpkg.com/zego-zim-web@2.16.0/index.js';
  const CALL_KIT_URL =
      'https://unpkg.com/@zegocloud/zego-uikit-prebuilt@2.14.1/zego-uikit-prebuilt.js';
  let ready;
  let kit = null;
  let currentID = '';
  let currentToken = '';
  let pendingInit;

  function loadScript(url, globalName) {
    if (window[globalName]) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = url;
      script.async = true;
      script.crossOrigin = 'anonymous';
      script.onload = () => window[globalName]
          ? resolve()
          : reject(new Error('voice_sdk_missing_' + globalName));
      script.onerror = () => reject(new Error('voice_sdk_load_failed'));
      document.head.appendChild(script);
    });
  }

  function loadWebKit() {
    if (!ready) {
      ready = (async () => {
        await loadScript(ZIM_URL, 'ZIM');
        await loadScript(CALL_KIT_URL, 'ZegoUIKitPrebuilt');
      })().catch((error) => {
        ready = null; // Allow a retry after transient CDN/network failure.
        throw error;
      });
    }
    return ready;
  }

  function forgetKit() {
    window.ExpressVoiceUI?.reset();
    if (kit) {
      try { kit.destroy(); } catch (_) {}
    }
    kit = null;
    currentID = '';
    currentToken = '';
  }

  async function initialize(appID, token, userID, userName) {
    if (!Number.isInteger(Number(appID)) ||
        Number(appID) <= 0 || !token || !userID) {
      throw new Error('voice_session_invalid');
    }
    if (kit && currentID === userID && currentToken === token) {
      return true;
    }
    if (pendingInit) await pendingInit;
    if (kit && currentID === userID && currentToken === token) {
      return true;
    }
    pendingInit = (async () => {
      await loadWebKit();
      forgetKit();
      const ctor = window.ZegoUIKitPrebuilt;
      // Official production auth: signed Token04 from the existing Edge
      // Function. A test token/ServerSecret in JavaScript is forbidden.
      const kitToken = ctor.generateKitTokenForProduction(
          Number(appID), token, null, userID, userName || 'Express');
      const instance = ctor.create(kitToken);
      instance.addPlugins({ZIM: window.ZIM});
      // Official Web Call Kit setting for invitations to Android/iOS when
      // the recipient app is backgrounded or closed. Delivery still requires
      // the native push provider configuration and physical-device E2E tests.
      instance.setCallInvitationConfig({
        enableNotifyWhenAppRunningInBackgroundOrQuit: true,
        // Presentation callbacks only; ZEGO owns signaling and RTC audio.
        ...(window.ExpressVoiceUI?.invitationOptions() || {}),
      });
      kit = instance;
      currentID = userID;
      currentToken = token;
      return true;
    })();
    try { return await pendingInit; }
    finally { pendingInit = null; }
  }

  async function send(callID, peerUserID, peerUserName, timeout, resourceID) {
    if (pendingInit) await pendingInit;
    if (!kit) throw new Error('voice_web_not_ready');
    if (!callID || !peerUserID || peerUserID === currentID) {
      throw new Error('voice_invalid_peer');
    }
    const api = window.ZegoUIKitPrebuilt;
    const options = {
      callees: [{userID: peerUserID, userName: peerUserName || 'Express'}],
      callType: api.InvitationTypeVoiceCall,
      timeout: Math.min(60, Math.max(1, Number(timeout) || 30)),
      // Explicit room ID supplied by our authorized Zego Edge Function.
      roomID: callID,
      data: JSON.stringify({app: 'express', type: 'private_trip_voice'}),
    };
    if (resourceID) {
      options.notificationConfig = {
        resourcesID: resourceID,
        title: 'Llamada de Express',
        message: 'Tienes una llamada de tu viaje',
      };
    }
    const result = await kit.sendCallInvitation(options);
    if (result && Array.isArray(result.errorInvitees) &&
        result.errorInvitees.length > 0) {
      throw new Error('voice_peer_unavailable');
    }
    return true;
  }

  window.expressWebVoiceInit = initialize;
  window.expressWebVoiceSend = send;
  window.expressWebVoiceRelease = () => {
    forgetKit();
    return true;
  };
})();

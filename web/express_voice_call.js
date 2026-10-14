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
  let peerName = 'Contacto de Express';
  let phoneView = null;
  let callClock = null;
  let callStartedAt = 0;

  // Presentation only. The ZEGO room keeps ownership of the microphone,
  // hang-up control, audio transport and call invitation state.
  function removePhoneView() {
    if (callClock !== null) {
      clearInterval(callClock);
      callClock = null;
    }
    if (phoneView) phoneView.remove();
    phoneView = null;
    callStartedAt = 0;
  }

  function updatePhoneStatus(connected) {
    if (!phoneView) return;
    const status = phoneView.querySelector('.express-phone-status');
    if (status) status.textContent = connected
        ? 'En llamada' : 'Conectando audio…';
  }

  function displayPhoneView() {
    removePhoneView();
    if (!document.getElementById('express-phone-call-style')) {
      const style = document.createElement('style');
      style.id = 'express-phone-call-style';
      style.textContent = `
        .express-phone-view {
          position: fixed; inset: 0; z-index: 2147483000;
          pointer-events: none; box-sizing: border-box;
          display: flex; flex-direction: column; align-items: center;
          justify-content: center;
          padding: 26px 20px max(155px, 24vh);
          color: #fff; text-align: center; font-family: inherit;
        }
        .express-phone-label {
          font-size: 12px; font-weight: 800; letter-spacing: 2px;
          text-transform: uppercase; color: #93bafa;
          margin-bottom: 30px;
        }
        .express-phone-avatar {
          height: 116px; width: 116px; border-radius: 50%;
          background: linear-gradient(145deg,#2563eb,#0a338a);
          border: 4px solid rgba(255,255,255,.12);
          display: grid; place-items: center;
          font-size: 48px; font-weight: 800;
          box-shadow: 0 14px 42px rgba(0,0,0,.35);
        }
        .express-phone-peer {
          font-size: clamp(21px,5.2vw,30px); font-weight: 800;
          margin-top: 24px; max-width: min(90vw,400px);
          overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
        }
        .express-phone-status {
          font-size: 15px; color: #b9c7de; margin-top: 10px;
        }
        .express-phone-duration {
          font-size: 20px; letter-spacing: 2px;
          font-variant-numeric: tabular-nums; margin-top: 10px;
        }
        @media (max-height: 580px) {
          .express-phone-view { padding-bottom: 95px; }
          .express-phone-label { margin-bottom: 12px; }
          .express-phone-avatar { height: 78px; width: 78px; font-size: 32px; }
          .express-phone-peer { margin-top: 10px; }
        }
      `;
      document.head.appendChild(style);
    }
    const view = document.createElement('div');
    view.className = 'express-phone-view';
    view.setAttribute('aria-hidden', 'true');
    view.innerHTML = `
      <div class="express-phone-label">Express · Llamada de voz</div>
      <div class="express-phone-avatar"></div>
      <div class="express-phone-peer"></div>
      <div class="express-phone-status">Conectando audio…</div>
      <div class="express-phone-duration">00:00</div>
    `;
    const name = (peerName || 'Contacto de Express').trim();
    view.querySelector('.express-phone-peer').textContent = name;
    view.querySelector('.express-phone-avatar').textContent =
        name.slice(0, 1).toLocaleUpperCase() || 'E';
    document.body.appendChild(view);
    phoneView = view;
    callStartedAt = Date.now();
    callClock = setInterval(() => {
      if (!phoneView) return;
      const elapsed = Math.max(0, Math.floor((Date.now() - callStartedAt) / 1000));
      const minutes = String(Math.floor(elapsed / 60)).padStart(2, '0');
      const seconds = String(elapsed % 60).padStart(2, '0');
      const label = phoneView.querySelector('.express-phone-duration');
      if (label) label.textContent = minutes + ':' + seconds;
    }, 1000);
  }

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
    removePhoneView();
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
        // Called for BOTH incoming and outgoing invitations, immediately
        // before joining the ZEGO room. InvitationTypeVoiceCall by itself
        // does not disable the default video-conference-style room screen.
        onSetRoomConfigBeforeJoining: (callType) => ({
          turnOnCameraWhenJoining: false,
          turnOnMicrophoneWhenJoining: true,
          showMyCameraToggleButton: false,
          showMyMicrophoneToggleButton: true,
          showAudioVideoSettingsButton: false,
          showScreenSharingButton: false,
          showLayoutButton: false,
          showPinButton: false,
          showRoomDetailsButton: false,
          showTextChat: false,
          showUserList: false,
          showNonVideoUser: false,
          showOnlyAudioUser: false,
          showRoomTimer: false,
          autoHideFooter: false,
          showLeavingView: false,
          onJoinRoom: () => displayPhoneView(),
          onUserJoin: () => updatePhoneStatus(true),
          onLeaveRoom: () => removePhoneView(),
        }),
        onIncomingCallReceived: (callID, caller) => {
          peerName = caller && caller.userName
              ? caller.userName : 'Contacto de Express';
        },
        onCallInvitationEnded: () => removePhoneView(),
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
    peerName = peerUserName || 'Contacto de Express';
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

/**
 * Express web voice-call presentation only. ZEGO remains responsible for
 * invitation delivery, room audio, microphone and hang-up controls.
 * No app IDs, tokens, private participant data or telephony logic live here.
 */
(function () {
  'use strict';

  let peerName = 'Usuario Express';
  let durationHandle = null;
  let startedAt = 0;
  const callOverlayId = 'express-voice-dialog';

  function displayName(value) {
    const result = String(value || '').trim();
    return result ? result.slice(0, 64) : 'Usuario Express';
  }

  function initials(value) {
    return Array.from(displayName(value))[0].toLocaleUpperCase('es');
  }

  function stopClock() {
    if (durationHandle !== null) clearInterval(durationHandle);
    durationHandle = null;
    startedAt = 0;
  }

  function hideDialog() {
    document.getElementById(callOverlayId)?.remove();
  }

  function clearPresentation() {
    hideDialog();
    stopClock();
  }

  function callIcon() {
    return '<svg viewBox="0 0 24 24" width="24" height="24" ' +
      'fill="currentColor" aria-hidden="true"><path d="M6.62 10.79a15.05 ' +
      '15.05 0 006.59 6.59l2.2-2.2a1 1 0 011.01-.24c1.12.37 2.33.57 ' +
      '3.58.57a1 1 0 011 1V20a1 1 0 01-1 1C10.61 21 3 13.39 3 ' +
      '4a1 1 0 011-1h3.5a1 1 0 011 1c0 1.25.2 2.46.57 ' +
      '3.58a1 1 0 01-.24 1.01l-2.21 2.2z"/></svg>';
  }

  // Never insert user-supplied names with innerHTML: only static icons/layout
  // are markup. Names are assigned through textContent.
  function showDialog(kind, name, actions) {
    hideDialog();
    peerName = displayName(name);
    const view = document.createElement('section');
    view.id = callOverlayId;
    view.className = 'express-voice-dialog express-voice-dialog--' + kind;
    view.setAttribute('role', 'dialog');
    view.setAttribute('aria-modal', 'true');
    view.setAttribute('aria-label',
      kind === 'incoming' ? 'Llamada de voz entrante' : 'Llamada de voz saliente');
    view.innerHTML =
      '<div class="express-voice-panel">' +
        '<div class="express-voice-brand"><span class="express-voice-brand-dot"></span> EXPRESS</div>' +
        '<div class="express-voice-eyebrow">LLAMADA PRIVADA · SOLO AUDIO</div>' +
        '<div class="express-voice-avatar" aria-hidden="true"></div>' +
        '<h2 class="express-voice-peer"></h2>' +
        '<p class="express-voice-state" aria-live="polite"></p>' +
        '<div class="express-voice-pulse" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></div>' +
        '<div class="express-voice-actions"></div>' +
        '<p class="express-voice-footnote">Tus números personales permanecen privados</p>' +
      '</div>';
    view.querySelector('.express-voice-avatar').textContent = initials(peerName);
    view.querySelector('.express-voice-peer').textContent = peerName;
    view.querySelector('.express-voice-state').textContent = kind === 'incoming'
      ? 'Te está llamando por Express' : 'Llamando…';

    const row = view.querySelector('.express-voice-actions');
    for (const action of actions) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'express-voice-action express-voice-action--' + action.kind;
      btn.setAttribute('aria-label', action.label);
      btn.innerHTML = callIcon() + '<span></span>';
      btn.querySelector('span').textContent = action.label;
      btn.addEventListener('click', () => {
        hideDialog();
        action.run();
      }, {once: true});
      row.appendChild(btn);
    }
    document.body.appendChild(view);
  }

  function roomForeground() {
    const view = document.createElement('section');
    view.className = 'express-voice-room-foreground';
    view.setAttribute('aria-label', 'Llamada de voz de Express');
    view.innerHTML =
      '<div class="express-voice-room-brand">EXPRESS · LLAMADA DE VOZ</div>' +
      '<div class="express-voice-room-avatar" aria-hidden="true"></div>' +
      '<h2 class="express-voice-room-name"></h2>' +
      '<p class="express-voice-room-status">Conectando audio…</p>' +
      '<div class="express-voice-pulse" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></div>' +
      '<p class="express-voice-room-privacy">Comunicación privada, sin cámara</p>';
    view.querySelector('.express-voice-room-avatar').textContent = initials(peerName);
    view.querySelector('.express-voice-room-name').textContent = peerName;
    return view;
  }

  function setClockText() {
    if (!startedAt) return;
    const seconds = Math.max(0, Math.floor((Date.now() - startedAt) / 1000));
    const formatted = String(Math.floor(seconds / 60)).padStart(2, '0') +
      ':' + String(seconds % 60).padStart(2, '0');
    document.querySelectorAll('.express-voice-room-status').forEach((node) => {
      node.textContent = 'En llamada · ' + formatted;
    });
  }

  function beginClock() {
    stopClock();
    startedAt = Date.now();
    setClockText();
    durationHandle = setInterval(setClockText, 1000);
  }

  function invitationOptions() {
    return {
      enableCustomCallInvitationWaitingPage: true,
      enableCustomCallInvitationDialog: true,
      onWaitingPageWhenSending: (_callType, callees, cancel) => {
        const person = Array.isArray(callees) && callees[0];
        showDialog('outgoing', person?.userName || peerName, [
          {kind: 'hangup', label: 'Cancelar', run: () => cancel()},
        ]);
      },
      onConfirmDialogWhenReceiving: (_callType, caller, refuse, accept) => {
        showDialog('incoming', caller?.userName || 'Usuario Express', [
          {kind: 'hangup', label: 'Rechazar', run: () => refuse()},
          {kind: 'accept', label: 'Responder', run: () => accept()},
        ]);
      },
      onSetRoomConfigBeforeJoining: (callType) => {
        hideDialog();
        // ZEGO handles audio streams and device permissions. This only hides
        // video-looking tiles/buttons and draws a phone-style foreground.
        if (callType !== window.ZegoUIKitPrebuilt.InvitationTypeVoiceCall) {
          return {};
        }
        return {
          showPreJoinView: false,
          turnOnMicrophoneWhenJoining: true,
          turnOnCameraWhenJoining: false,
          showMyCameraToggleButton: false,
          showMyMicrophoneToggleButton: true,
          showAudioVideoSettingsButton: false,
          showScreenSharingButton: false,
          showTextChat: false,
          showUserList: false,
          showLayoutButton: false,
          showPinButton: false,
          showOnlyAudioUser: false,
          showNonVideoUser: false,
          showWaitingCallAcceptAudioVideoView: false,
          showLeavingView: false,
          autoHideFooter: false,
          maxUsers: 2,
          requireRoomForegroundView: roomForeground,
          onJoinRoom: beginClock,
          onLeaveRoom: clearPresentation,
        };
      },
      onCallInvitationEnded: clearPresentation,
    };
  }

  window.ExpressVoiceUI = {
    invitationOptions,
    setPeer: (name) => {peerName = displayName(name);},
    reset: () => {
      clearPresentation();
      peerName = 'Usuario Express';
    },
  };
})();

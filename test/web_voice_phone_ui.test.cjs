// Minimal DOM + ZEGO Web SDK contract harness. No real credentials or network.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

test('Taxi and Envíos open only a phone-style audio room', async () => {
  const nodes = [];
  const makeNode = (tag) => {
    const slots = new Map();
    const node = {
      tagName: tag, id: '', className: '', innerHTML: '',
      textContent: '', attributes: {}, removed: false,
      setAttribute(key, val) { this.attributes[key] = val; },
      querySelector(selector) {
        if (!slots.has(selector)) slots.set(selector, {textContent: ''});
        return slots.get(selector);
      },
      remove() { this.removed = true; }
    };
    return node;
  };
  const document = {
    head: {appendChild(el) { nodes.push(el); }},
    body: {appendChild(el) { nodes.push(el); }},
    createElement: makeNode,
    getElementById(id) { return nodes.find((el) => el.id === id && !el.removed); }
  };
  let options;
  let config;
  let destroyed = false;
  const ZegoUIKitPrebuilt = {
    InvitationTypeVoiceCall: 1,
    generateKitTokenForProduction: () => 'signed_kit_token',
    create: () => ({
      addPlugins: ({ZIM}) => assert.ok(ZIM),
      setCallInvitationConfig(value) {config = value;},
      async sendCallInvitation(value) {options = value; return {errorInvitees: []};},
      destroy() {destroyed = true;}
    })
  };
  const window = {ZIM: {}, ZegoUIKitPrebuilt};
  let timerOn = false;
  const script = fs.readFileSync('web/express_voice_call.js','utf8');
  vm.runInNewContext(script, {
    window, document, Date,
    setInterval: () => {timerOn = true; return 13;},
    clearInterval: () => {timerOn = false;},
  }, {filename: 'web/express_voice_call.js'});
  assert.equal(await window.expressWebVoiceInit(123456, 'signed_token_04', 'me', 'Mi nombre'), true);
  assert.equal(config.enableNotifyWhenAppRunningInBackgroundOrQuit, true);
  const room = config.onSetRoomConfigBeforeJoining(ZegoUIKitPrebuilt.InvitationTypeVoiceCall);
  assert.equal(room.turnOnCameraWhenJoining, false);
  assert.equal(room.turnOnMicrophoneWhenJoining, true);
  assert.equal(room.showMyCameraToggleButton, false);
  assert.equal(room.showMyMicrophoneToggleButton, true);
  assert.equal(room.showAudioVideoSettingsButton, false);
  assert.equal(room.showScreenSharingButton, false);
  assert.equal(room.showOnlyAudioUser, false);
  assert.equal(room.showNonVideoUser, false);
  assert.equal(room.autoHideFooter, false);
  assert.equal(room.showTextChat, false);

  // Callee gets the real caller name from the invitation, never a phone number.
  config.onIncomingCallReceived('call-in', {userName:'Cliente de Express'});
  room.onJoinRoom();
  let panel = nodes.find((el) => el.className === 'express-phone-view');
  assert.ok(panel);
  assert.equal(panel.attributes['aria-hidden'], 'true');
  assert.equal(panel.querySelector('.express-phone-peer').textContent, 'Cliente de Express');
  assert.match(panel.innerHTML, /Conectando audio…/);
  assert.equal(timerOn, true);
  room.onUserJoin();
  assert.equal(panel.querySelector('.express-phone-status').textContent, 'En llamada');
  room.onLeaveRoom();
  assert.equal(panel.removed, true);
  assert.equal(timerOn, false);

  // Caller uses the same room configuration and keeps invitation signaling.
  assert.equal(await window.expressWebVoiceSend('call-out','peer','Conductor',30), true);
  assert.equal(options.callType, ZegoUIKitPrebuilt.InvitationTypeVoiceCall);
  assert.equal(options.roomID, 'call-out');
  room.onJoinRoom();
  panel = nodes.filter((el) => el.className === 'express-phone-view').at(-1);
  assert.equal(panel.querySelector('.express-phone-peer').textContent, 'Conductor');
  config.onCallInvitationEnded();
  assert.equal(panel.removed, true);
  assert.equal(window.expressWebVoiceRelease(), true);
  assert.equal(destroyed, true);
});

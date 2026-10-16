import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato de la burbuja circular de acceso directo. Son comprobaciones de
/// fuente: no sustituyen las pruebas en emulador.
void main() {
  final bubble = File(
    'android_overlay/kotlin/com/express/usuario1/DriverBubbleService.kt',
  ).readAsStringSync();
  final plugin = File(
    'android_overlay/kotlin/com/express/usuario1/FloatingOfferPlugin.kt',
  ).readAsStringSync();
  final card = File(
    'android_overlay/kotlin/com/express/usuario1/FloatingOfferService.kt',
  ).readAsStringSync();
  final dart = File('lib/driver_floating_offers.dart').readAsStringSync();
  final home = File('lib/video_style_home.dart').readAsStringSync();
  final manifestScript =
      File('.github/scripts/apply_floating_overlay.py').readAsStringSync();

  test('bubble is a separate circular service with the Express logo', () {
    expect(bubble, contains('class DriverBubbleService'));
    expect(bubble, contains('GradientDrawable.OVAL'));
    expect(bubble, contains('R.mipmap.ic_launcher'));
    expect(bubble, contains('"Abrir Express"'));
  });

  test('bubble supports drag, edge snap, tap-to-open and dismiss target', () {
    expect(bubble, contains('MotionEvent.ACTION_MOVE'));
    expect(bubble, contains('snapToEdge('));
    expect(bubble, contains('openApp()'));
    expect(bubble, contains('showDismissTarget()'));
    expect(bubble, contains('isOverDismissTarget('));
    expect(bubble, contains('emitBubble("dismissed")'));
    expect(bubble, contains('emitBubble("open_app")'));
  });

  test('bubble never carries offer data or accepts a ride', () {
    expect(bubble, isNot(contains('EXTRA_PRICE')));
    expect(bubble, isNot(contains('EXTRA_ROUTE')));
    expect(bubble, isNot(contains('"accept"')));
    expect(bubble, isNot(contains('emitAction(')));
  });

  test('offer card no longer creates a fixed bubble', () {
    expect(card, isNot(contains('Separate small Express shortcut')));
    expect(card, isNot(contains('wm.addView(shortcut')));
  });

  test('plugin exposes bubble show/hide and returns bubble events', () {
    expect(plugin, contains('"bubbleShow"'));
    expect(plugin, contains('"bubbleHide"'));
    expect(plugin, contains('fun emitBubble(action: String)'));
    expect(plugin, contains('"bubbleEvent"'));
    expect(plugin, contains('Settings.canDrawOverlays(ctx)'));
  });

  test('manifest script registers the bubble service idempotently', () {
    expect(manifestScript, contains('BUBBLE_SERVICE'));
    expect(manifestScript, contains('.DriverBubbleService'));
  });

  test('Dart hides the bubble when Express is foreground or driver is unavailable', () {
    expect(dart, contains('bubbleShown'));
    expect(dart, contains('!appInForeground'));
    expect(dart, contains('driverAvailable'));
    expect(dart, contains('await _syncBubble(wanted: false)'));
    expect(dart, contains('bridge.showBubble()'));
    expect(dart, contains('bridge.hideBubble()'));
  });

  test('dismissal is remembered for the session and cleared on resume or re-enable', () {
    expect(dart, contains('Future<void> setBubbleDismissed(bool dismissed)'));
    expect(home, contains('setBubbleDismissed(true)'));
    expect(home, contains("if (action == 'dismissed')"));
    expect(home, contains('setBubbleDismissed(false)'));
  });

  test('bubble events are not treated as offer focus', () {
    expect(dart, contains("if (call.method == 'bubbleEvent')"));
    final bubbleBranch = dart.indexOf("if (call.method == 'bubbleEvent')");
    final offerBranch = dart.indexOf("if (call.method == 'action')");
    expect(bubbleBranch, greaterThan(-1));
    expect(offerBranch, greaterThan(bubbleBranch));
  });

  test('driver offer popup header sits below the online/earnings bar', () {
    expect(home, contains('top: 76,'));
  });
}

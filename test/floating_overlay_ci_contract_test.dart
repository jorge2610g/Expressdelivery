import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File('.github/workflows/build-android.yml').readAsStringSync();

  test('the overlay step runs after the Android scaffold exists and before plugin regeneration', () {
    final scaffold = workflow.indexOf('- name: Create Android platform scaffold');
    final overlay = workflow.indexOf('- name: Apply driver floating offer overlay');
    final regen = workflow.indexOf('- name: Regenerate and verify Android plugin registration');
    expect(scaffold, greaterThan(-1));
    expect(overlay, greaterThan(scaffold),
        reason: 'applying before the scaffold would be erased by rm -rf android');
    expect(regen, greaterThan(overlay));
  });

  test('native Firebase messaging dependency is added to the Android app module', () {
    final script = File('.github/scripts/apply_floating_overlay.py').readAsStringSync();
    expect(script, contains("patch_app_gradle(root.parent.parent / 'build.gradle.kts')"));
    expect(script, contains('com.google.firebase:firebase-messaging'));
    expect(script, contains("text.rstrip() + '\\n\\ndependencies {\\n' + FIREBASE_DEPS + '}\\n'"));
  });

  test('the overlay sources and script are versioned in the repository', () {
    expect(File('.github/scripts/apply_floating_overlay.py').existsSync(), isTrue);
    expect(File('android_overlay/kotlin/com/express/usuario1/FloatingOfferService.kt').existsSync(),
        isTrue);
    expect(File('android_overlay/kotlin/com/express/usuario1/FloatingOfferPlugin.kt').existsSync(),
        isTrue);
    expect(File('android_overlay/res/layout/express_floating_offer.xml').existsSync(), isTrue);
  });

  test('compact overlay opens original popup, never accepts or rejects outside the app', () {
    final xml = File('android_overlay/res/layout/express_floating_offer.xml')
        .readAsStringSync();
    final native = File('android_overlay/kotlin/com/express/usuario1/FloatingOfferService.kt')
        .readAsStringSync();
    expect(xml, contains('offer_progress'));
    expect(xml, contains('offer_remaining'));
    expect(xml, isNot(contains('offer_accept')));
    expect(xml, isNot(contains('offer_reject')));
    expect(native, contains('emitAction(this, id, "open")'));
    expect(native, contains('handler.postDelayed(this, 250L)'));
    expect(native, contains('expiresAt - System.currentTimeMillis()'));
  });

  test('tap survives a Flutter engine restart and stays a non-accepting action', () {
    final plugin = File(
      'android_overlay/kotlin/com/express/usuario1/FloatingOfferPlugin.kt',
    ).readAsStringSync();
    final flutter = File('lib/video_style_home.dart').readAsStringSync();
    expect(plugin, contains('"consumePendingOpen"'));
    expect(plugin, contains('PENDING_OPEN_PREFS'));
    expect(plugin, contains('.putString("offerId", offerId)'));
    expect(plugin, contains('age in 0L..120000L'));
    expect(flutter, contains('_restoreNativeFloatingOfferOpen()'));
    // Revalidation stays server-side; notification taps only skip the
    // overlay-setting gate (fromNotification), never accept on the user's behalf.
    expect(flutter, contains('_revalidateFloatingOfferFocus('));
    expect(flutter, contains('fromNotification: fromNotification'));
  });

  test('native overlay reuses the same Express task instead of starting a blank Flutter task', () {
    final native = File(
      'android_overlay/kotlin/com/express/usuario1/FloatingOfferService.kt',
    ).readAsStringSync();
    expect(native, contains('activityManager.appTasks.firstOrNull'));
    expect(native, contains('ownTask.moveToFront()'));
    expect(native, isNot(contains('Intent.FLAG_ACTIVITY_CLEAR_TOP')));
    expect(native, isNot(contains('Intent.FLAG_ACTIVITY_REORDER_TO_FRONT')));
    expect(workflow, contains('android:taskAffinity'));
  });

  test('tapping a driver push must preserve mounted map and selected request', () {
    final shell = File('lib/connected_experience.dart').readAsStringSync();
    final driver = File('lib/video_style_home.dart').readAsStringSync();
    // Notification taps use their own focus channel so the overlay setting
    // cannot block the detail; the mounted map is preserved either way.
    expect(shell, contains('driverNotificationOfferFocus.value = requestId;'));
    expect(driver, contains('driverNotificationOfferFocus.addListener'));
    expect(driver, contains('FLOATING_OFFER_POPUP_PRESENTED'));
    expect(driver, contains('FLOATING_OFFER_OPEN_BLOCKED'));
  });

  test('the service removes the previous card without stopping itself on show', () {
    final service = File(
            'android_overlay/kotlin/com/express/usuario1/FloatingOfferService.kt')
        .readAsStringSync();
    final show = service.indexOf('private fun show(');
    final hideCall = service.indexOf('        hide()\n        val id', show);
    expect(show, greaterThan(-1));
    expect(hideCall, -1, reason: 'show() must not call hide(), which stops the service');
    expect(service.contains('removeCard()'), isTrue);
    expect(service.contains('catch (_: RuntimeException)'), isTrue);
  });
}

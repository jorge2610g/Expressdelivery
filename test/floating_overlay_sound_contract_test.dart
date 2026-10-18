import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato de la alerta sonora y del gesto nativo de la ventana flotante.
/// La reproducción real y el movimiento del dedo se validan en el emulador/teléfono.
void main() {
  late String native;

  setUpAll(() {
    native = File(
      'android_overlay/kotlin/com/express/usuario1/FloatingOfferService.kt',
    ).readAsStringSync();
  });

  test('alert plays once per offer and never duplicates', () {
    expect(native, contains('if (alertOfferId == id) return'));
    expect(native, contains('startAlert(id, seconds)'));
  });

  test('alert stops when the card closes, on dismiss and on destroy', () {
    final removeCard = native.substring(
      native.indexOf('private fun removeCard()'),
      native.indexOf('private fun hide()'),
    );
    expect(removeCard, contains('stopAlert()'));
    expect(native, contains('private fun dismiss() {\n        stopAlert()'));
    expect(native, contains('override fun onDestroy() {\n        stopAlert()'));
  });

  test('alert is capped at 30 seconds and loops only while visible', () {
    expect(native, contains('minOf(seconds, 30) * 1000L'));
    expect(native, contains('isLooping = true'));
  });

  test('alert respects silent, vibrate and do-not-disturb modes', () {
    expect(
      native,
      contains('audio.ringerMode != AudioManager.RINGER_MODE_NORMAL'),
    );
    expect(
      native,
      contains('currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL'),
    );
    expect(native, contains('USAGE_NOTIFICATION_RINGTONE'));
  });

  test('swipe follows the finger and fling-out stops the sound first', () {
    expect(native, contains('MotionEvent.ACTION_MOVE'));
    expect(native, contains('view.translationX = dx'));
    final fling = native.substring(
      native.indexOf('private fun flingOut('),
      native.indexOf('private fun settleBack('),
    );
    expect(fling.indexOf('stopAlert()'), lessThan(fling.indexOf('animate()')));
    expect(fling, contains('withEndAction { dismiss() }'));
  });

  test('the card uses the official Express logo and the 30 s cap', () {
    final layout = File(
      'android_overlay/res/layout/express_floating_offer.xml',
    ).readAsStringSync();

    expect(layout, isNot(contains('@mipmap/ic_launcher')));
    expect(layout, isNot(contains('🚕')));
    expect(layout, contains('android:src="@drawable/ic_express_notification_large"'));
    expect(native, contains('DEFAULT_BANNER_SECONDS = 30'));
  });
}

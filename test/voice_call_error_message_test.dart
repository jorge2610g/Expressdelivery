import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/voice_call_error_message.dart';

void main() {
  test('minified 429 call_cooldown becomes a clear retry message', () {
    const raw = 'minified:a9E(status: 429, details: '
        '{ok: false, code: call_cooldown, '
        'message: Espera unos segundos antes de volver a llamar})';
    final message = expressVoiceCallMessage(StateError(raw));
    expect(message, contains('Espera unos segundos'));
    expect(message, isNot(contains('429')));
    expect(message, isNot(contains('call_cooldown')));
    expect(message, isNot(contains('minified')));
  });

  test('unknown technical errors never reach passenger UI', () {
    final message = expressVoiceCallMessage(
      StateError('ZegoFlutterEngine is not defined'),
    );
    expect(message, contains('no están disponibles'));
    expect(message, isNot(contains('ZegoFlutterEngine')));
  });

  test('permission and ended-trip errors are actionable', () {
    expect(expressVoiceCallMessage(StateError('trip_not_active')),
        contains('viaje esté activo'));
    expect(expressVoiceCallMessage(StateError('not_trip_participant')),
        contains('No tienes permiso'));
  });
}

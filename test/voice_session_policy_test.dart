import 'package:expressdelivery/voice_session_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14, 12);

  group('voiceSessionNeedsFreshLogin', () {
    test('entra de nuevo si el último intento falló', () {
      expect(
        voiceSessionNeedsFreshLogin(
          tokenExpiresAt: now.add(const Duration(hours: 5)),
          now: now,
          lastAttemptFailed: true,
        ),
        isTrue,
      );
    });

    test('entra de nuevo si no se sabe cuándo vence la llave', () {
      expect(
        voiceSessionNeedsFreshLogin(
          tokenExpiresAt: null,
          now: now,
          lastAttemptFailed: false,
        ),
        isTrue,
      );
    });

    test('solo renueva cuando la llave tiene margen de sobra', () {
      expect(
        voiceSessionNeedsFreshLogin(
          tokenExpiresAt: now.add(const Duration(hours: 2)),
          now: now,
          lastAttemptFailed: false,
        ),
        isFalse,
      );
    });

    test('entra de nuevo cuando faltan menos de 30 minutos', () {
      expect(
        voiceSessionNeedsFreshLogin(
          tokenExpiresAt: now.add(const Duration(minutes: 20)),
          now: now,
          lastAttemptFailed: false,
        ),
        isTrue,
      );
    });

    test('entra de nuevo justo a los 30 minutos del vencimiento', () {
      expect(
        voiceSessionNeedsFreshLogin(
          tokenExpiresAt: now.add(const Duration(minutes: 30)),
          now: now,
          lastAttemptFailed: false,
        ),
        isTrue,
      );
    });

    test('entra de nuevo si la llave ya venció', () {
      expect(
        voiceSessionNeedsFreshLogin(
          tokenExpiresAt: now.subtract(const Duration(minutes: 1)),
          now: now,
          lastAttemptFailed: false,
        ),
        isTrue,
      );
    });
  });

  group('voiceTokenLifetime', () {
    test('usa la duración que indica el servidor', () {
      expect(
        voiceTokenLifetime({'tokenExpiresInSeconds': 21600}),
        const Duration(hours: 6),
      );
      expect(
        voiceTokenLifetime({'tokenExpiresInSeconds': '3600'}),
        const Duration(hours: 1),
      );
    });

    test('usa 6 horas si falta o no es válida', () {
      expect(voiceTokenLifetime(const {}), const Duration(hours: 6));
      expect(
        voiceTokenLifetime({'tokenExpiresInSeconds': 'x'}),
        const Duration(hours: 6),
      );
      expect(
        voiceTokenLifetime({'tokenExpiresInSeconds': 0}),
        const Duration(hours: 6),
      );
    });
  });
}

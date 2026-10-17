import 'dart:io';

import 'package:expressdelivery/ride_offer_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

/// Forma real de las excepciones de PostgREST, con el texto del servidor.
String postgrest(String message) =>
    "PostgrestException(message: $message, code: P0001, details: null, hint: null)";

void main() {
  group('server errors become user messages', () {
    test('expired or unavailable offer', () {
      expect(
        friendlyRideOfferError(postgrest('Oferta vencida o no disponible')),
        'Esta solicitud ya no está disponible. Puedes elegir otra.',
      );
      expect(
        friendlyRideOfferError(
          postgrest('Solicitud vencida o sin vencimiento válido'),
        ),
        'Esta solicitud ya no está disponible. Puedes elegir otra.',
      );
      expect(
        friendlyRideOfferError(postgrest('La solicitud ya venció')),
        'Esta solicitud ya no está disponible. Puedes elegir otra.',
      );
    });

    test('own request and operating zone have their own messages', () {
      expect(
        friendlyRideOfferError(
          postgrest('No puedes asignarte tu propia solicitud'),
        ),
        'No puedes aceptar tu propia solicitud.',
      );
      expect(
        friendlyRideOfferError(
          postgrest('Oferta fuera de tu entorno operativo'),
        ),
        'Esta solicitud no está disponible para tu zona o servicio.',
      );
    });

    test('authorization failure asks to sign in again', () {
      expect(
        friendlyRideOfferError(postgrest('No autorizado')),
        contains('iniciar sesión'),
      );
    });

    test('unknown errors never expose PostgreSQL details', () {
      final message = friendlyRideOfferError(
        postgrest('relation "secret_table" does not exist'),
      );

      expect(message, 'No pudimos aceptar la solicitud. Intenta de nuevo.');
      expect(message, isNot(contains('PostgrestException')));
      expect(message, isNot(contains('P0001')));
      expect(message, isNot(contains('Bad Request')));
    });

    test('null and empty errors fall back to the generic message', () {
      expect(
        friendlyRideOfferError(null),
        'No pudimos aceptar la solicitud. Intenta de nuevo.',
      );
    });
  });

  group('screen uses the mapping', () {
    test('accept failures no longer show the raw exception', () {
      final home = File('lib/video_style_home.dart').readAsStringSync();

      expect(home, isNot(contains("'No se pudo aceptar la tarifa: ' + e.toString()")));
      expect(home, isNot(contains("'No se pudo aceptar: ' + e.toString()")));
      expect(home, contains('friendlyRideOfferError(e)'));
    });
  });
}

import 'dart:io';

import 'package:expressdelivery/web_main.dart' as web;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes the registration query link used by the QR', () {
    expect(
      web.expressIsDriverRegistrationUri(
        Uri.parse('https://expressviajes.online/?registro=conductor'),
      ),
      isTrue,
    );
  });

  test('recognizes the direct /registro/conductor link', () {
    expect(
      web.expressIsDriverRegistrationUri(
        Uri.parse('https://expressviajes.online/registro/conductor'),
      ),
      isTrue,
    );
    expect(
      web.expressIsDriverRegistrationUri(
        Uri.parse('https://expressviajes.online/registro/conductor/'),
      ),
      isTrue,
    );
  });

  test('does not route customer pages into driver registration', () {
    expect(
      web.expressIsDriverRegistrationUri(
        Uri.parse('https://expressviajes.online/'),
      ),
      isFalse,
    );
    expect(
      web.expressIsDriverRegistrationUri(
        Uri.parse('https://expressviajes.online/registro/pasajero'),
      ),
      isFalse,
    );
  });

  test(
    'approved driver sees only the app welcome, not the pending invitation',
    () {
      final portal = File(
        'lib/driver_registration_web_portal.dart',
      ).readAsStringSync();
      expect(portal, contains("if (_approvalStatus != 'approved') ...["));
      expect(portal, contains('¡Bienvenido a Express!'));
      expect(portal, contains('Descargar app'));
    },
  );
}

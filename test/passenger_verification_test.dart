import 'dart:io';

import 'package:expressdelivery/passenger_verification.dart';
import 'package:flutter_test/flutter_test.dart';

PassengerVerificationState _state({
  bool photo = true,
  bool identity = false,
  bool selfie = false,
  bool hasPhoto = false,
  List<String> submitted = const [],
}) {
  return PassengerVerificationState.fromJson({
    'profile_photo_required': photo,
    'identity_document_required': identity,
    'face_selfie_required': selfie,
    'has_profile_photo': hasPhoto,
    'submitted_documents': submitted,
  });
}

void main() {
  test('configuración inicial: solo se pide la foto de perfil', () {
    final state = _state();
    expect(state.pendingSteps, [PassengerVerificationStep.profilePhoto]);
    expect(state.isComplete, isFalse);
  });

  test('con la foto ya subida y sin carnet ni selfie activos, todo está listo', () {
    final state = _state(hasPhoto: true);
    expect(state.pendingSteps, isEmpty);
    expect(state.isComplete, isTrue);
  });

  test('el carnet pide frente y reverso, sin repetir los ya enviados', () {
    final state = _state(
      hasPhoto: true,
      identity: true,
      submitted: const ['identity_front'],
    );
    expect(state.pendingSteps, [PassengerVerificationStep.identityBack]);
  });

  test('la selfie se pide solo cuando el administrador la activa', () {
    expect(_state(hasPhoto: true).pendingSteps, isEmpty);
    expect(
      _state(hasPhoto: true, selfie: true).pendingSteps,
      [PassengerVerificationStep.faceSelfie],
    );
    expect(
      _state(hasPhoto: true, selfie: true, submitted: const ['face_selfie'])
          .isComplete,
      isTrue,
    );
  });

  test('si la foto de perfil no es obligatoria, no aparece como pendiente', () {
    expect(_state(photo: false).pendingSteps, isEmpty);
  });

  test('el orden de los pasos es foto, carnet frente, carnet reverso y selfie', () {
    final state = _state(identity: true, selfie: true);
    expect(state.pendingSteps, [
      PassengerVerificationStep.profilePhoto,
      PassengerVerificationStep.identityFront,
      PassengerVerificationStep.identityBack,
      PassengerVerificationStep.faceSelfie,
    ]);
  });

  test('tipos de documento que guarda la base', () {
    expect(passengerDocumentTypeFor(PassengerVerificationStep.identityFront),
        'identity_front');
    expect(passengerDocumentTypeFor(PassengerVerificationStep.identityBack),
        'identity_back');
    expect(passengerDocumentTypeFor(PassengerVerificationStep.faceSelfie),
        'face_selfie');
    expect(passengerDocumentTypeFor(PassengerVerificationStep.profilePhoto),
        isNull);
  });

  test('solo se aceptan JPG, PNG y WebP', () {
    expect(passengerImageExtension('foto.JPG'), 'jpg');
    expect(passengerImageExtension('foto.jpeg'), 'jpg');
    expect(passengerImageExtension('foto.png'), 'png');
    expect(passengerImageExtension('foto.webp'), 'webp');
    expect(passengerImageExtension('documento.pdf'), isNull);
    expect(passengerImageExtension('sinextension'), isNull);
  });

  test('las rutas empiezan en la carpeta del propio pasajero', () {
    expect(
      passengerProfilePhotoPath(userId: 'u-1', extension: 'jpg'),
      'u-1/profile.jpg',
    );
    expect(
      passengerVerificationObjectPath(
        userId: 'u-1',
        documentType: 'identity_front',
        extension: 'png',
        timestampMs: 42,
      ),
      'u-1/identity_front-42.png',
    );
  });

  test('tipo de contenido coherente con la extensión', () {
    expect(passengerContentType('png'), 'image/png');
    expect(passengerContentType('webp'), 'image/webp');
    expect(passengerContentType('jpg'), 'image/jpeg');
  });

  test('el archivo de la app usa solo los buckets de verificación', () {
    final source = File('lib/passenger_verification.dart').readAsStringSync();
    expect(source, contains("storage.from('passenger-profile')"));
    expect(source, contains("storage.from('passenger-verification')"));
    expect(source, contains("'passenger_set_profile_photo'"));
    expect(source, contains("'passenger_submit_verification_document'"));
    expect(source, contains("'passenger_verification_state'"));
  });

  test('crear viaje y volver a buscar pasan por la verificación', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(
      home,
      contains(
        'if (_expressOfflineBlocked(context)) return;\n'
        '    if (!await ensurePassengerVerified(context)) return;',
      ),
    );
    expect(
      home,
      contains(
        "    required num fare,\n  }) async {\n"
        "    if (!await ensurePassengerVerified(context)) return;",
      ),
    );
  });
}

import 'package:expressdelivery/driver_registration_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> completeDriverState() => <String, dynamic>{
        'vehicle': <String, dynamic>{
          'brand': 'Toyota',
          'model': 'Yaris',
          'plate': 'ABCD12',
        },
        'documents': <Map<String, dynamic>>[
          <String, dynamic>{
            'requirement_id': 'identity',
            'code': 'identity_card',
            'label': 'Documento de identidad',
            'document_type': 'national_id',
            'verification_method': 'manual',
            'status': 'verified',
          },
        ],
      };

  final requirements = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'identity',
      'code': 'identity_card',
      'label': 'Documento de identidad',
      'document_type': 'national_id',
      'verification_method': 'manual',
      'required': true,
    },
  ];

  test('does not require an active plan when zone enforcement is disabled', () {
    final missing = driverRegistrationMissingItems(
      state: completeDriverState(),
      requirements: requirements,
      subscriptionUsable: false,
      subscriptionRequired: false,
    );

    expect(missing, isEmpty);
  });

  test('requires an active plan when zone enforcement is enabled', () {
    final missing = driverRegistrationMissingItems(
      state: completeDriverState(),
      requirements: requirements,
      subscriptionUsable: false,
      subscriptionRequired: true,
    );

    expect(
      missing,
      contains('Suscripción: activa un plan para conectarte.'),
    );
  });

  test('keeps subscription out of unrelated onboarding errors when optional', () {
    final state = completeDriverState();
    state['documents'] = <Map<String, dynamic>>[];

    final missing = driverRegistrationMissingItems(
      state: state,
      requirements: requirements,
      subscriptionUsable: false,
      subscriptionRequired: false,
    );

    expect(
      missing,
      contains('Documento de identidad: falta enviar el carné.'),
    );
    expect(
      missing.where((item) => item.startsWith('Suscripción:')),
      isEmpty,
    );
  });
  test('only the rejected profile photo is reported when identity is approved', () {
    final state = completeDriverState();
    state['documents'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'requirement_id': 'identity',
        'code': 'identity_card',
        'label': 'Documento de identidad',
        'document_type': 'national_id',
        'verification_method': 'manual',
        'status': 'verified',
        'review_parts': <String, dynamic>{
          'front': <String, dynamic>{
            'status': 'approved',
            'path': 'front.jpg',
          },
          'back': <String, dynamic>{
            'status': 'approved',
            'path': 'back.jpg',
          },
          'selfie': <String, dynamic>{
            'status': 'approved',
            'path': 'selfie.jpg',
          },
          'profile': <String, dynamic>{
            'status': 'rejected',
            'path': 'profile.jpg',
            'reason': 'Foto borrosa',
          },
        },
      },
    ];

    final missing = driverRegistrationMissingItems(
      state: state,
      requirements: requirements,
      subscriptionUsable: true,
      subscriptionRequired: false,
    );

    expect(missing, contains('Foto de perfil: rechazado · Foto borrosa'));
    expect(
      missing.where((item) => item.startsWith('Carné ·')),
      isEmpty,
    );
  });
}

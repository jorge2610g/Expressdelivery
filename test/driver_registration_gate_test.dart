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
  test('Preview blocks an expired licence, Production rollout stays unchanged', () {
    final state = completeDriverState();
    final documents = List<Map<String,dynamic>>.from(state['documents'] as List);
    documents.add({
      'requirement_id':'license',
      'document_type':'driver_license',
      'status':'verified',
      'document_number':'LIC123',
      'front_object_path':'front.jpg',
      'back_object_path':'back.jpg',
      'expires_at':DateTime.now().toUtc().subtract(
        const Duration(days:2)).toIso8601String(),
    });
    state['documents'] = documents;
    final catalog = [...requirements,{
      'id':'license','code':'driver_license','label':'Licencia',
      'required':true,'require_number':true,'require_front':true,
      'require_back':true,
    }];
    final preview = driverRegistrationMissingItems(
      state:state, requirements:catalog,
      subscriptionUsable:true,subscriptionRequired:false,
      expirationEnforced:true,
    );
    expect(preview.any((m)=>m.startsWith('Licencia: vencido')),isTrue);
    final production = driverRegistrationMissingItems(
      state:state, requirements:catalog,
      subscriptionUsable:true,subscriptionRequired:false,
      expirationEnforced:false,
    );
    expect(production,isEmpty);
  });

  test('new enforced licence needs expiration; a legacy approved one is preserved', () {
    final state=completeDriverState();
    final today=DateTime.now().toUtc();
    final documents = List<Map<String,dynamic>>.from(state['documents'] as List);
    final licence = <String,dynamic>{
      'requirement_id':'license',
      'document_type':'driver_license','status':'verified',
      'document_number':'LIC123','front_object_path':'front.jpg',
      'back_object_path':'back.jpg',
      'created_at':today.toIso8601String(),
    };
    documents.add(licence);
    state['documents']=documents;
    final catalog=[...requirements,{
      'id':'license','code':'driver_license','label':'Licencia',
      'required':true,'require_number':true,'require_front':true,
      'require_back':true,
      'expiration_required':true,
      'expiration_required_since':today.subtract(
        const Duration(days:1)).toIso8601String(),
    }];
    final missing=driverRegistrationMissingItems(
      state:state,requirements:catalog,
      subscriptionUsable:true,subscriptionRequired:false,
      expirationEnforced:true,
    );
    expect(missing,contains('Licencia: falta fecha de vencimiento.'));
    licence['created_at']=today.subtract(const Duration(days:30))
        .toIso8601String();
    final legacy=driverRegistrationMissingItems(
      state:state,requirements:catalog,
      subscriptionUsable:true,subscriptionRequired:false,
      expirationEnforced:true,
    );
    expect(legacy,isEmpty);
  });

}

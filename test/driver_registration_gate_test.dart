import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_registration_gate.dart';

void main() {
  final approvedOnboarding = <String, dynamic>{
    'documents': [
      <String, dynamic>{
        'code': 'identity',
        'verification_method': 'manual',
        'status': 'verified',
      },
    ],
    'vehicle': <String, dynamic>{
      'brand': 'Toyota',
      'model': 'Yaris',
      'plate': 'ABCD12',
    },
  };

  test('allows driver without a paid plan when backend permits connection', () {
    final missing = driverRegistrationMissingItems(
      state: approvedOnboarding,
      requirements: const [],
      subscriptionAllowed: true,
    );
    expect(missing, isEmpty);
  });

  test('requires a plan when backend denies subscription access', () {
    final missing = driverRegistrationMissingItems(
      state: approvedOnboarding,
      requirements: const [],
      subscriptionAllowed: false,
    );
    expect(missing, contains('Suscripción: activa un plan para conectarte.'));
  });

  test('identity verification remains required with subscription permission', () {
    final missing = driverRegistrationMissingItems(
      state: <String, dynamic>{
        ...approvedOnboarding,
        'documents': <Map<String, dynamic>>[],
      },
      requirements: const [],
      subscriptionAllowed: true,
    );
    expect(missing, contains('Documento de identidad: falta verificar tu identidad.'));
    expect(missing.any((item) => item.startsWith('Suscripción:')), isFalse);
  });
}

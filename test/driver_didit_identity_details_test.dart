import 'package:expressdelivery/widgets/driver_didit_identity_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only selected Didit fields are shown to verified user',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverDiditIdentityDetails(
            verification: <String, dynamic>{
              'status': 'verified',
              'country_code': 'BO',
              'result': <String, dynamic>{
                'document_type': 'ID',
                'issuing_state': 'BO',
                'identity': <String, dynamic>{
                  'document_number': '000000123',
                  'first_name': 'Test',
                  'last_name': 'Driver',
                  'date_of_birth': '2000-01-02',
                  'date_of_issue': '2022-05-09',
                  'expiration_date': '2032-05-09',
                  'nationality': 'BO',
                  'gender': 'F',
                  'address': 'SECRET ADDRESS MUST NEVER APPEAR',
                  'marital_status': 'SECRET MARITAL STATUS',
                },
              },
            },
          ),
        ),
      ),
    ));
    expect(find.text('Datos verificados con Didit'), findsOneWidget);
    expect(find.text('Test Driver'), findsOneWidget);
    expect(find.text('000000123'), findsOneWidget);
    expect(find.text('09/05/2032'), findsOneWidget);
    expect(find.text('Femenino'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);
  });

  testWidgets('unapproved identity never displays the verified summary',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DriverDiditIdentityDetails(
          verification: <String, dynamic>{'status': 'review'},
        ),
      ),
    ));
    expect(find.text('Datos verificados con Didit'), findsNothing);
  });

  testWidgets('missing expiration is not incorrectly called non-expiring',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DriverDiditIdentityDetails(
          verification: <String, dynamic>{
            'status': 'verified',
            'result': <String, dynamic>{
              'identity': <String, dynamic>{},
            },
          },
        ),
      ),
    ));
    expect(find.textContaining('revisión pendiente'), findsWidgets);
  });
}

import 'package:expressdelivery/cancellation_fee_confirmation.dart';
import 'package:expressdelivery/services/express_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _QuotedCancellationService extends ExpressService {
  _QuotedCancellationService(this.quote);

  final Map<String, dynamic> quote;

  @override
  Future<Map<String, dynamic>> cancellationFeeQuoteForRideRequest(
    String rideRequestId,
  ) async =>
      quote;

  @override
  Future<Map<String, dynamic>> cancellationFeeQuote(String tripId) async =>
      quote;
}

Future<num?> _openPassengerCancellationQuote(
  WidgetTester tester,
  Map<String, dynamic> quote,
) async {
  num? result;
  final service = _QuotedCancellationService(quote);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await confirmRideRequestCancellationFee(
                context,
                service,
                'ride-request-test',
              );
            },
            child: const Text('Cancelar viaje'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Cancelar viaje'));
  await tester.pumpAndSettle();
  return result;
}

Future<num?> _openDriverCancellationQuote(
  WidgetTester tester,
  Map<String, dynamic> quote,
) async {
  num? result;
  final service = _QuotedCancellationService(quote);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await confirmTripCancellationFee(
                context,
                service,
                'trip-test',
              );
            },
            child: const Text('Cancelar viaje'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Cancelar viaje'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('passenger sees fee immediately after driver accepts, without driver grace copy',
      (tester) async {
    await _openPassengerCancellationQuote(tester, {
      'fee': 500,
      'currency': 'CLP',
      'role': 'passenger',
      'grace_seconds': 0,
    });

    expect(find.text('Cancelar con cobro'), findsOneWidget);
    expect(
      find.textContaining('El conductor ya aceptó el viaje.'),
      findsOneWidget,
    );
    expect(find.textContaining('CLP 500'), findsOneWidget);
    expect(find.textContaining('Quedan'), findsNothing);
    expect(find.text('Seguir esperando'), findsOneWidget);
    expect(find.text('Cancelar y aceptar el cobro'), findsOneWidget);
  });

  testWidgets('driver sees their five-minute grace countdown', (tester) async {
    await _openDriverCancellationQuote(tester, {
      'fee': 500,
      'currency': 'CLP',
      'role': 'driver',
      'grace_seconds': 120,
    });

    expect(find.text('Cancelar con cobro'), findsOneWidget);
    expect(find.textContaining('Quedan 2:00'), findsOneWidget);
    expect(find.textContaining('El conductor ya aceptó el viaje.'), findsNothing);
  });
}

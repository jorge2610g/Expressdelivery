import 'package:expressdelivery/design/express_tokens.dart';
import 'package:expressdelivery/restaurant_courier_page.dart';
import 'package:expressdelivery/restaurant_courier_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(String name, String status, [String? trip]) => {
      'id': name,
      'customer_name': name,
      'destination_address': 'Calle $name',
      'service_type': 'deliver_only',
      'delivery_fee': 2500,
      'currency': 'CLP',
      'created_at': '2026-11-24T03:22:32',
      'status': status,
      'trip_status': trip,
    };

void main() {
  test('agrupa las solicitudes por estado', () {
    expect(courierRequestBucket(_row('a', 'searching')), CourierRequestFilter.active);
    expect(courierRequestBucket(_row('a', 'offers_received')), CourierRequestFilter.active);
    expect(courierRequestBucket(_row('a', 'driver_selected', 'in_progress')),
        CourierRequestFilter.active);
    expect(courierRequestBucket(_row('a', 'driver_selected', 'completed')),
        CourierRequestFilter.done);
    expect(courierRequestBucket(_row('a', 'cancelled')), CourierRequestFilter.cancelled);
    expect(courierRequestBucket(_row('a', 'driver_selected', 'cancelled')),
        CourierRequestFilter.cancelled);
    expect(courierRequestBucket(_row('a', 'expired')), CourierRequestFilter.noDriver);
  });

  testWidgets('Mis solicitudes filtra por estado', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ExpressTheme.light(),
      home: Scaffold(
        body: RestaurantCourierRequestsPage(merchantId: 'm1', debugRows: [
          _row('Uno', 'searching'),
          _row('Dos', 'driver_selected', 'completed'),
          _row('Tres', 'cancelled'),
          _row('Cuatro', 'cancelled'),
        ]),
      ),
    ));
    expect(find.text('Todas (4)'), findsOneWidget);
    expect(find.text('En proceso (1)'), findsOneWidget);
    expect(find.text('Completadas (1)'), findsOneWidget);
    expect(find.text('Canceladas (2)'), findsOneWidget);
    expect(find.text('Sin repartidor (0)'), findsNothing);
    // Al abrir se ven solo las pendientes.
    expect(find.text('Uno'), findsOneWidget);
    expect(find.text('Dos'), findsNothing);
    expect(find.text('Tres'), findsNothing);

    await tester.tap(find.text('Todas (4)'));
    await tester.pump();
    expect(find.text('Dos'), findsOneWidget);
    expect(find.text('Tres'), findsOneWidget);

    await tester.tap(find.text('Canceladas (2)'));
    await tester.pump();
    expect(find.text('Tres'), findsOneWidget);
    expect(find.text('Cuatro'), findsOneWidget);
    expect(find.text('Uno'), findsNothing);
    expect(find.text('Dos'), findsNothing);

    await tester.tap(find.text('Completadas (1)'));
    await tester.pump();
    expect(find.text('Dos'), findsOneWidget);
    expect(find.text('Tres'), findsNothing);
  });

  testWidgets('perfil del local que solo pide repartidor', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ExpressTheme.light(),
      home: const Scaffold(
        body: RestaurantCourierProfilePage(
          merchantId: 'm1',
          debugEmail: 'local@correo.cl',
          debugProfile: {
            'role': 'owner',
            'name': 'Pizzería Norte',
            'address': 'Barros Arana, Iquique',
            'latitude': -20.23,
            'longitude': -70.13,
            'country_code': 'CL',
            'currency': 'CLP',
            'courier_pricing': 'flat',
            'courier_flat_fare': 2500,
          },
        ),
      ),
    ));
    expect(find.text('Pizzería Norte'), findsOneWidget);
    expect(find.text('local@correo.cl'), findsOneWidget);
    expect(find.textContaining('por envío'), findsOneWidget);
    expect(find.text('Ubicación predeterminada del local'), findsOneWidget);
    expect(find.text('Guardar ubicación'), findsOneWidget);
    // Nada del perfil de un restaurante con menú.
    expect(find.text('Pedido mínimo'), findsNothing);
    expect(find.text('Descripción'), findsNothing);
    expect(find.text('Logo'), findsNothing);
  });
}

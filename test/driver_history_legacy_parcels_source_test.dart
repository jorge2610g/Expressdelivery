import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('driver history includes legacy parcels but never marketplace orders', () {
    final source = File('lib/express_account_pages.dart').readAsStringSync();
    expect(source, contains('widget.service.myTrips('));
    expect(source, contains('widget.service.myDeliveries('));
    expect(source, contains("delivery['courier_id']?.toString() != widget.service.userId"));
    expect(source, contains("delivery['marketplace_order_id'] != null"));
    expect(source, contains("delivery['channel']?.toString() != widget.service.runtimeChannel"));
    expect(source, contains('A legacy Envíos lookup must never hide'));
    expect(source, contains('deliveries = <Map<String, dynamic>>[];'));
    expect(source, contains("originalStatus != 'delivered'"));
    expect(source, contains("normalized['status'] = 'completed'"));
    expect(source, contains("..['destination_address'] = delivery['dropoff_address']"));
  });

  test('driver parcel history renders map, fare and clear service labels', () {
    final source = File('lib/express_account_pages.dart').readAsStringSync();
    expect(source, contains("widget.driver ? 'Historial de viajes y envíos'"));
    expect(source, contains("entry.delivery || route['service_mode'] == 'parcel'"));
    expect(source, contains("isParcel ? 'Mapa del envío' : 'Mapa del viaje'"));
    expect(source, contains("label: isParcel ? 'Código de envío' : 'Código de viaje'"));
  });
}

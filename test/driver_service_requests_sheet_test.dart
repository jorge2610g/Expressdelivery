import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_service_requests_sheet.dart';

void main() {
  test('legacy response preserves the one-service Taxi experience', () {
    expect(approvedDriverRequestTabs(null), ['ride']);
    expect(approvedDriverRequestTabs({}), ['ride']);
  });

  test('only approved categories appear and respect stable order', () {
    expect(approvedDriverRequestTabs([
      {'service_key': 'market', 'status': 'approved'},
      {'service_key': 'parcel', 'status': 'pending'},
      {'service_key': 'ride', 'status': 'approved'},
    ]), ['ride', 'market']);

    expect(approvedDriverRequestTabs([
      {'service_key': 'market', 'status': 'approved'},
      {'service_key': 'parcel', 'status': 'approved'},
      {'service_key': 'ride', 'status': 'approved'},
    ]), ['ride', 'parcel', 'market']);

    expect(approvedDriverRequestTabs([
      {'service_key': 'ride', 'status': 'rejected'},
      {'service_key': 'market', 'status': 'approved'},
    ]), ['market']);
  });

  test('marketplace jobs are separate from personal parcels', () {
    expect(deliveryRequestServiceKey({'marketplace_order_id': 'order-1'}),
        'market');
    expect(deliveryRequestServiceKey({'marketplace_order_id': null}),
        'parcel');
    expect(deliveryRequestServiceKey({}), 'parcel');
  });
}

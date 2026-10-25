import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/core/driver_work_scope.dart';

void main() {
  test('primary driver recognizes taxi, parcels, and restaurant orders', () {
    expect(
      expressPrimaryDriverApprovedServices(['ride', 'parcel', 'market']),
      {'ride', 'parcel', 'market'},
    );
    expect(expressPrimaryDriverApprovedServices(['market']), {'market'});
  });

  test('delivery jobs require matching parcel or restaurant permission', () {
    final parcel = <String, dynamic>{
      'id': 'parcel-1',
      'marketplace_order_id': null,
    };
    final restaurant = <String, dynamic>{
      'id': 'order-1',
      'marketplace_order_id': 'marketplace-1',
    };

    expect(
      expressPrimaryDriverMayReceiveDelivery(parcel, {'ride', 'parcel'}),
      isTrue,
    );
    expect(
      expressPrimaryDriverMayReceiveDelivery(parcel, {'ride'}),
      isFalse,
    );
    expect(
      expressPrimaryDriverMayReceiveDelivery(restaurant, {'ride', 'parcel'}),
      isFalse,
    );
    expect(
      expressPrimaryDriverMayReceiveDelivery(restaurant, {'market'}),
      isTrue,
    );
  });
}

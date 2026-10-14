import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/core/driver_work_scope.dart';

void main() {
  test('primary driver allows taxi and parcels, never restaurant couriers', () {
    expect(
      expressPrimaryDriverApprovedServices(['ride', 'parcel', 'market']),
      {'ride', 'parcel'},
    );
    expect(expressPrimaryDriverApprovedServices(['market']), isEmpty);
  });

  test('primary driver sees customer parcel jobs only with parcel permission', () {
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
      isFalse,
    );
  });
}

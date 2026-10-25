/// Service categories available to the driver inside the primary Express app.
const Set<String> expressPrimaryDriverServices = <String>{
  'ride',
  'parcel',
  'market',
};

Set<String> expressPrimaryDriverApprovedServices(
  Iterable<String> authorizedServices,
) => authorizedServices.where(expressPrimaryDriverServices.contains).toSet();

/// The legacy delivery_requests table serves passenger parcels and restaurant
/// orders. Each delivery requires its matching service authorization.
bool expressPrimaryDriverMayReceiveDelivery(
  Map<String, dynamic> delivery,
  Set<String> approvedServices,
) {
  final serviceKey = delivery['marketplace_order_id'] == null
      ? 'parcel'
      : 'market';
  return approvedServices.contains(serviceKey);
}

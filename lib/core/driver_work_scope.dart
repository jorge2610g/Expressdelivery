/// Service categories available to the driver inside the primary Express app.
///
/// Customer-facing restaurant ordering stays in the primary app; restaurant
/// courier dispatch belongs to the separate Express_Repartidor application.
/// The shared Supabase service permissions are not altered here.
const Set<String> expressPrimaryDriverServices = <String>{'ride', 'parcel'};

Set<String> expressPrimaryDriverApprovedServices(
  Iterable<String> authorizedServices,
) => authorizedServices.where(expressPrimaryDriverServices.contains).toSet();

/// The legacy delivery_requests table also serves passenger parcels.
/// A restaurant order must never be offered to the driver in the primary app.
bool expressPrimaryDriverMayReceiveDelivery(
  Map<String, dynamic> delivery,
  Set<String> approvedServices,
) =>
    delivery['marketplace_order_id'] == null &&
    approvedServices.contains('parcel');

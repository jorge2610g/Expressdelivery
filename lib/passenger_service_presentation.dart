/// Presentation-only logic for the passenger service selector.
/// The real vehicle category and fare quote remain unchanged for parcels.
List<Map<String, dynamic>> expressPassengerServiceCards(
  List<Map<String, dynamic>> taxiServices, {
  required bool parcelAvailable,
}) {
  final cards = taxiServices
      .where((service) {
        final key = service['service_key']?.toString();
        return key != 'parcel' && key != 'delivery';
      })
      .map((service) => Map<String, dynamic>.from(service))
      .toList();
  if (parcelAvailable) {
    cards.add({
      'service_key': 'parcel',
      'name': 'Envíos',
      'vehicle_type': 'parcel',
      'enabled': true,
      'passenger_visible': true,
    });
  }
  return cards;
}

String expressSelectedPassengerServiceKey(String serviceType, String category) =>
    serviceType == 'delivery' ? 'parcel' : category;

/// Displays the authoritative pricing multiplier instead of its % delta.
/// 1.0 => Demanda; 1.5 => Demanda 1.5; 2.0 => Demanda 2.
String expressDemandMultiplierLabel(num? rawMultiplier) {
  final multiplier = rawMultiplier?.toDouble();
  if (multiplier == null || !multiplier.isFinite || multiplier <= 0 ||
      (multiplier - 1).abs() < 0.005) {
    return 'Demanda';
  }
  final rounded = multiplier.toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '');
  return 'Demanda $rounded';
}


/// Presentation-only parcel services. Each renders through the EXACT same
/// _RideServiceSlots and _RideServiceSlotButton as Taxi. Authorizing a driver
/// for these categories remains strictly a backend responsibility.
const List<Map<String, dynamic>> expressParcelVehicleCards = [
  {
    'service_key': 'moto',
    'name': 'Moto',
    'vehicle_type': 'motorcycle',
    'enabled': true,
    'passenger_visible': true,
  },
  {
    'service_key': 'auto',
    'name': 'Auto',
    'vehicle_type': 'car',
    'enabled': true,
    'passenger_visible': true,
  },
  {
    'service_key': 'carga',
    'name': 'Carga',
    'vehicle_type': 'cargo',
    'enabled': true,
    'passenger_visible': true,
  },
];

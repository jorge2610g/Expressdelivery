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

/// Display only validated pricing multipliers in whole or half steps.
/// The quote and the label must agree; never round a real ×1,35 into ×1,5.
/// All other values stay pending until pricing is configured to half-steps.
String expressDemandMultiplierLabel(num? rawMultiplier) {
  final multiplier = rawMultiplier?.toDouble();
  if (multiplier == null || !multiplier.isFinite || multiplier < 1) {
    return 'Demanda · verificando';
  }
  final twice = multiplier * 2;
  final steps = twice.round();
  if ((twice - steps).abs() > 0.00001) {
    return 'Demanda · verificando';
  }
  if (steps == 2) {
    return 'Demanda normal · ×1';
  }
  final whole = steps ~/ 2;
  final value = steps.isEven ? '$whole' : '$whole,5';
  return 'Demanda · ×$value';
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

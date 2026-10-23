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

/// Etiqueta de demanda autorizada por el propietario: "Demanda x1", "Demanda x1.5",
/// "Demanda x2", "Demanda x2.5", "Demanda x3". La palabra es fija; cambia el
/// multiplicador. Punto decimal y sin ".0" en enteros. Normal = 1; nunca vacía.
String expressDemandMultiplierBadge(num? rawMultiplier) {
  final multiplier = rawMultiplier?.toDouble();
  if (multiplier == null || !multiplier.isFinite || multiplier <= 0 ||
      (multiplier - 1).abs() < 0.005) {
    return 'Demanda x1';
  }
  final rounded = multiplier.toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '');
  return 'Demanda x$rounded';
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

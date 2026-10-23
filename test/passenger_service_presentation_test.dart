import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/passenger_service_presentation.dart';

void main() {
  test('Envíos only appears in card row when the zone enables it', () {
    final original = <Map<String, dynamic>>[
      {'service_key': 'express', 'name': 'Express', 'enabled': true},
      {'service_key': 'motorcycle', 'name': 'Mototaxi', 'enabled': true},
    ];
    final off = expressPassengerServiceCards(original, parcelAvailable: false);
    expect(off.map((s) => s['service_key']), ['express', 'motorcycle']);
    final on = expressPassengerServiceCards(original, parcelAvailable: true);
    expect(on.map((s) => s['service_key']),
        ['express', 'motorcycle', 'parcel']);
    expect(on.last['name'], 'Envíos');
    expect(on.last['enabled'], isTrue);
    expect(original, hasLength(2)); // Never mutate the real service catalog.
  });

  test('Parcel selection is UI-only and restores actual Taxi service card', () {
    expect(expressSelectedPassengerServiceKey('ride', 'express'), 'express');
    expect(expressSelectedPassengerServiceKey('delivery', 'express'), 'parcel');
    expect(expressSelectedPassengerServiceKey('ride', 'motorcycle'), 'motorcycle');
  });

  test('Parcel services retain Taxi card widget with distinct names', () {
    expect(expressParcelVehicleCards.map((s) => s['service_key']),
        ['moto', 'auto', 'carga']);
    expect(expressParcelVehicleCards.map((s) => s['name']),
        ['Moto', 'Auto', 'Carga']);
    expect(expressParcelVehicleCards.every(
        (s) => s['passenger_visible'] == true), isTrue);
    expect(expressSelectedPassengerServiceKey('ride', 'express'), 'express');
  });

  test('demand label is "Demanda xN" with a dot decimal, never empty', () {
    // Formato autorizado por el propietario: palabra fija, multiplicador real.
    expect(expressDemandMultiplierBadge(1), 'Demanda x1');
    expect(expressDemandMultiplierBadge(1.0), 'Demanda x1');
    expect(expressDemandMultiplierBadge(1.5), 'Demanda x1.5');
    expect(expressDemandMultiplierBadge(2), 'Demanda x2');
    expect(expressDemandMultiplierBadge(2.0), 'Demanda x2');
    expect(expressDemandMultiplierBadge(2.5), 'Demanda x2.5');
    expect(expressDemandMultiplierBadge(3), 'Demanda x3');
    expect(expressDemandMultiplierBadge(3.5), 'Demanda x3.5');
    expect(expressDemandMultiplierBadge(4.25), 'Demanda x4.25');
    expect(expressDemandMultiplierBadge(10), 'Demanda x10');
    expect(expressDemandMultiplierBadge(.9), 'Demanda x0.9');
    expect(expressDemandMultiplierBadge(null), 'Demanda x1');
    expect(expressDemandMultiplierBadge(double.nan), 'Demanda x1');
    expect(expressDemandMultiplierBadge(0), 'Demanda x1');
  });
}

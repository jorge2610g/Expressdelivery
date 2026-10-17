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

  test('demand label is "Demanda por N" with a comma decimal, never empty', () {
    expect(expressDemandMultiplierBadge(1), 'Demanda por 1');
    expect(expressDemandMultiplierBadge(1.0), 'Demanda por 1');
    expect(expressDemandMultiplierBadge(1.5), 'Demanda por 1,5');
    expect(expressDemandMultiplierBadge(2), 'Demanda por 2');
    expect(expressDemandMultiplierBadge(2.5), 'Demanda por 2,5');
    expect(expressDemandMultiplierBadge(3.0), 'Demanda por 3');
    expect(expressDemandMultiplierBadge(3.5), 'Demanda por 3,5');
    expect(expressDemandMultiplierBadge(4.25), 'Demanda por 4,25');
    expect(expressDemandMultiplierBadge(10), 'Demanda por 10');
    expect(expressDemandMultiplierBadge(.9), 'Demanda por 0,9');
    expect(expressDemandMultiplierBadge(null), 'Demanda por 1');
    expect(expressDemandMultiplierBadge(double.nan), 'Demanda por 1');
    expect(expressDemandMultiplierBadge(0), 'Demanda por 1');
  });
}

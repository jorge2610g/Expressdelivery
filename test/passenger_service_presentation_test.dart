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

  test('Demand badge always states the actual multiplier, not a percent', () {
    expect(expressDemandMultiplierLabel(1), 'Demanda normal · ×1,0');
    expect(expressDemandMultiplierLabel(1.0), 'Demanda normal · ×1,0');
    expect(expressDemandMultiplierLabel(1.5), 'Demanda · ×1,5');
    expect(expressDemandMultiplierLabel(1.05), 'Demanda · ×1,05');
    expect(expressDemandMultiplierLabel(2), 'Demanda · ×2');
    expect(expressDemandMultiplierLabel(3.0), 'Demanda · ×3');
    expect(expressDemandMultiplierLabel(4.25), 'Demanda · ×4,25');
    expect(expressDemandMultiplierLabel(.9), 'Demanda baja · ×0,9');
    expect(expressDemandMultiplierLabel(.5), 'Demanda baja · ×0,5');
  });

  test('Missing or invalid multiplier must not fake normal demand', () {
    expect(expressDemandMultiplierLabel(null), 'Demanda · calculando');
    expect(expressDemandMultiplierLabel(0), 'Demanda · calculando');
    expect(expressDemandMultiplierLabel(-1), 'Demanda · calculando');
    expect(
      expressDemandMultiplierLabel(double.nan),
      'Demanda · calculando',
    );
    expect(
      expressDemandMultiplierLabel(double.infinity),
      'Demanda · calculando',
    );
  });
}

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

  test('Demand is a multiplier badge, never a percentage or empty', () {
    expect(expressDemandMultiplierBadge(1), '1x');
    expect(expressDemandMultiplierBadge(1.0), '1x');
    expect(expressDemandMultiplierBadge(1.5), '1.5x');
    expect(expressDemandMultiplierBadge(2), '2x');
    expect(expressDemandMultiplierBadge(2.5), '2.5x');
    expect(expressDemandMultiplierBadge(3.0), '3x');
    expect(expressDemandMultiplierBadge(3.5), '3.5x');
    expect(expressDemandMultiplierBadge(4.25), '4.25x');
    expect(expressDemandMultiplierBadge(10), '10x');
    expect(expressDemandMultiplierBadge(.9), '0.9x');
    expect(expressDemandMultiplierBadge(null), '1x');
    expect(expressDemandMultiplierBadge(double.nan), '1x');
    expect(expressDemandMultiplierBadge(0), '1x');
  });
}

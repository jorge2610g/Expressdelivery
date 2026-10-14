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

  test('Shows normal demand and exact half-step factors only', () {
    expect(expressDemandMultiplierLabel(1), 'Demanda normal · ×1');
    expect(expressDemandMultiplierLabel(1.5), 'Demanda · ×1,5');
    expect(expressDemandMultiplierLabel(2), 'Demanda · ×2');
    expect(expressDemandMultiplierLabel(2.5), 'Demanda · ×2,5');
    expect(expressDemandMultiplierLabel(3), 'Demanda · ×3');
    expect(expressDemandMultiplierLabel(3.5), 'Demanda · ×3,5');
    expect(expressDemandMultiplierLabel(4), 'Demanda · ×4');
  });

  test('Never display a rounded factor that changes the real quote', () {
    for (final value in <num?>[null, 0, -1, .9, 1.1, 1.35, 3.1, 3.35]) {
      expect(
        expressDemandMultiplierLabel(value),
        'Demanda · verificando',
        reason: 'No informar un factor distinto al cobrado: $value',
      );
    }
    expect(expressDemandMultiplierLabel(double.nan), 'Demanda · verificando');
    expect(
      expressDemandMultiplierLabel(double.infinity),
      'Demanda · verificando',
    );
  });
}

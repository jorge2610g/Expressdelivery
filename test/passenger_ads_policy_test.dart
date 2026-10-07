import 'package:expressdelivery/passenger_ads_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production ads stay off unless explicitly enabled', () {
    expect(
      expressPassengerAdsEnabled(
        settings: const <String, dynamic>{},
        previewMode: false,
        placement: PassengerAdPlacement.home,
      ),
      isFalse,
    );
  });

  test('preview master flag enables both passenger placements by default', () {
    const settings = <String, dynamic>{
      'ads_passenger_preview_enabled': true,
    };

    expect(
      expressPassengerAdsEnabled(
        settings: settings,
        previewMode: true,
        placement: PassengerAdPlacement.home,
      ),
      isTrue,
    );
    expect(
      expressPassengerAdsEnabled(
        settings: settings,
        previewMode: true,
        placement: PassengerAdPlacement.activeTrip,
      ),
      isTrue,
    );
  });

  test('each passenger ad placement can be disabled remotely', () {
    const settings = <String, dynamic>{
      'ads_passenger_enabled': true,
      'ads_passenger_home_enabled': false,
      'ads_passenger_trip_enabled': true,
    };

    expect(
      expressPassengerAdsEnabled(
        settings: settings,
        previewMode: false,
        placement: PassengerAdPlacement.home,
      ),
      isFalse,
    );
    expect(
      expressPassengerAdsEnabled(
        settings: settings,
        previewMode: false,
        placement: PassengerAdPlacement.activeTrip,
      ),
      isTrue,
    );
  });
}

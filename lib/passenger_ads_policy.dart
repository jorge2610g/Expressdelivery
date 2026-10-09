enum PassengerAdPlacement {
  home,
  activeTrip,
}

bool expressPassengerAdsEnabled({
  required Map<String, dynamic> settings,
  required bool previewMode,
  required PassengerAdPlacement placement,
}) {
  final masterKey = previewMode
      ? 'ads_passenger_preview_enabled'
      : 'ads_passenger_enabled';
  if (settings[masterKey] != true) return false;

  switch (placement) {
    case PassengerAdPlacement.home:
      return (previewMode
          ? settings['ads_passenger_preview_home_enabled']
          : settings['ads_passenger_home_enabled']) != false;
    case PassengerAdPlacement.activeTrip:
      return (previewMode
          ? settings['ads_passenger_preview_trip_enabled']
          : settings['ads_passenger_trip_enabled']) != false;
  }
}

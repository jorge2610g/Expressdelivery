/// Decides whether the unified passenger web opens a service or a chooser.
/// This depends only on services allowed by the backend for the account/zone.
enum PassengerLandingDecision { unavailable, directService, selector }

PassengerLandingDecision passengerLandingDecision({
  required String mode,
  required int availableServiceCount,
}) {
  if (availableServiceCount <= 0) {
    return PassengerLandingDecision.unavailable;
  }
  // Adminexpress "always" explicitly requests the landing even for one
  // enabled service (e.g. Iquique Production with only Taxi enabled). Never
  // override that administrative choice using the available module count.
  if (mode == 'always') {
    return PassengerLandingDecision.selector;
  }
  // "auto" avoids an unnecessary chooser when only one service is enabled.
  // "direct" always opens the configured default service.
  if (mode == 'auto' && availableServiceCount > 1) {
    return PassengerLandingDecision.selector;
  }
  return PassengerLandingDecision.directService;
}

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
  // One allowed service means one dedicated screen, never a one-card selector.
  if (availableServiceCount == 1) {
    return PassengerLandingDecision.directService;
  }
  // Adminexpress direct mode can still choose a preferred service when
  // multiple are available. The other modes display the chooser.
  if (mode == 'auto' || mode == 'always') {
    return PassengerLandingDecision.selector;
  }
  return PassengerLandingDecision.directService;
}

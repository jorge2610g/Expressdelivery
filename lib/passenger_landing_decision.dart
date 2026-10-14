/// The passenger entry is exclusively determined by the available modules
/// returned by the zone-context RPC for the signed-in identity and its zone.
/// `mode` is retained for compatibility with existing callers / old zone rows,
/// but it must never override this automatic rule.
enum PassengerLandingDecision { unavailable, directService, selector }

PassengerLandingDecision passengerLandingDecision({
  required String mode,
  required int availableServiceCount,
}) {
  if (availableServiceCount <= 0) {
    return PassengerLandingDecision.unavailable;
  }
  if (availableServiceCount == 1) {
    return PassengerLandingDecision.directService;
  }
  return PassengerLandingDecision.selector;
}

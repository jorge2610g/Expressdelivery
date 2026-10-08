/// Navigation policy for the conductor's map.
///
/// An offer that expires restores navigation; accepting it hides navigation
/// through the passenger confirmation and the entire active ride, including
/// all transitions until the trip or delivery is completed/cancelled.
bool shouldLockDriverNavigation({
  required bool incomingOffer,
  required bool waitingPassenger,
  required bool hasActiveTrip,
  required bool hasActiveDelivery,
  required bool processingTransition,
}) =>
    incomingOffer ||
    waitingPassenger ||
    hasActiveTrip ||
    hasActiveDelivery ||
    processingTransition;

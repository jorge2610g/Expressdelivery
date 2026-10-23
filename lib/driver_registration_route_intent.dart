import 'driver_registration_route_intent_stub.dart'
    if (dart.library.html) 'driver_registration_route_intent_web.dart'
    as platform;

bool get hasPendingDriverRegistrationIntent =>
    platform.hasPendingDriverRegistrationIntent;

void rememberDriverRegistrationIntent() =>
    platform.rememberDriverRegistrationIntent();

void completeDriverRegistrationIntent() =>
    platform.completeDriverRegistrationIntent();

void clearDriverRegistrationIntent() =>
    platform.clearDriverRegistrationIntent();

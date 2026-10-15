import 'location_service.dart';
import 'map_provider.dart';
import 'offline_status.dart';
import 'services/express_service.dart';

/// Olvida en memoria lo que pertenece a la cuenta anterior. Se usa junto con
/// [clearAccountDeviceCaches] al cerrar sesión o al cambiar de cuenta.
void forgetAccountMemory() {
  ExpressConnectivityMonitor.instance.resetForAccountChange();
  ExpressLocationService.forgetInMemoryPosition();
  ExpressService.forgetPreloadedPassengerState();
  ExpressMapProvider.clearRouteMemory();
}

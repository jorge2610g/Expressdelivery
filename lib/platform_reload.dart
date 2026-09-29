import 'platform_reload_stub.dart'
    if (dart.library.html) 'platform_reload_web.dart' as platform;

void reloadExpressApp() => platform.reloadExpressApp();

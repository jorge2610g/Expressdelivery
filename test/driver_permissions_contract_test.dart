import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato: la pantalla «Permisos y servicios» del conductor informa el estado real
/// de cada servicio y nunca activa ni navega sola. Cada acción nace de un toque.
void main() {
  late String page;
  late String home;
  late String backgroundLocation;
  late String connected;
  late String androidBuildScript;

  setUpAll(() {
    page = File('lib/driver_permissions_page.dart').readAsStringSync();
    home = File('lib/video_style_home.dart').readAsStringSync();
    backgroundLocation =
        File('lib/driver_background_location.dart').readAsStringSync();
    connected = File('lib/connected_experience.dart').readAsStringSync();
    androidBuildScript =
        File('.github/scripts/apply_floating_overlay.py').readAsStringSync();
  });

  test('reads the real state of GPS, notifications, microphone and overlay', () {
    expect(page, contains('Geolocator.isLocationServiceEnabled()'));
    expect(page, contains('Geolocator.checkPermission()'));
    expect(page, contains('Permission.notification.status'));
    expect(page, contains('Permission.microphone.status'));
    expect(page, contains('isOverlayGranted()'));
    expect(page, contains('DriverFloatingOfferSettings(accountId: widget.service.userId)'));
  });

  test('reading the state never enables the bubble: the permission alone is not an opt-in', () {
    final start = page.indexOf('Future<List<_ServiceStatus>> _readStatuses()');
    final end = page.indexOf('Widget build(', start);
    final reading = page.substring(start, end);
    expect(reading, isNot(contains('.setEnabled(')));
    expect(reading, isNot(contains('enableBubble')));
    expect(reading, isNot(contains('requestBubbleActivation')));
    // Solo el onActivate del botón puede cambiar la preferencia.
    expect(RegExp('setBubbleEnabledByDriver').allMatches(reading).length, 1);
  });

  test('stale reads never overwrite a newer state', () {
    expect(page, contains('final seq = ++_loadSeq;'));
    expect(page, contains('seq != _loadSeq'));
  });

  test('the calls row reflects only the microphone permission', () {
    final start = page.indexOf("title: 'Llamadas'");
    final end = page.indexOf("title: 'Ventana flotante'", start);
    final row = page.substring(start, end);
    expect(row, contains('microphone.isGranted'));
    expect(row.toLowerCase(), isNot(contains('ventana')));
    expect(row.toLowerCase(), isNot(contains('burbuja')));
  });

  test('the floating window row asks for an explicit choice and never promises closed-app behavior', () {
    final start = page.indexOf("title: 'Ventana flotante'");
    final end = page.indexOf('    ];', start);
    final row = page.substring(start, end);
    expect(row, contains("'Desactivar burbuja'"));
    expect(row, contains("'Activar burbuja'"));
    expect(row, contains("'Acceso a la burbuja flotante'"));
    expect(row, contains('alwaysShowAction: true'));
    expect(row, contains('openOverlayPermissionSettings()'));
    expect(row, contains('setBubbleEnabledByDriver(widget.service, !bubbleOn)'));
    expect(row, isNot(contains('requestBubbleActivation')));
    expect(row, contains('Puede mostrar la burbuja sobre otras aplicaciones cuando Express está en segundo plano.'));
    expect(row, contains('depende de los permisos del teléfono'));
    expect(row.toLowerCase(), isNot(contains('oferta')));
    expect(row.toLowerCase(), isNot(contains('cerrad')));
  });

  test('state is refreshed when the user returns from system settings', () {
    expect(page, contains('WidgetsBindingObserver'));
    expect(page, contains('didChangeAppLifecycleState'));
    expect(page, contains('state == AppLifecycleState.resumed'));
  });

  test('opening the page never opens settings or requests a permission by itself', () {
    final start = page.indexOf('void initState()');
    final end = page.indexOf('@override', start);
    final initState = page.substring(start, end);
    expect(initState, isNot(contains('openAppSettings')));
    expect(initState, isNot(contains('openLocationSettings')));
    expect(initState, isNot(contains('openOverlayPermissionSettings')));
    expect(initState, isNot(contains('request')));
    expect(initState, isNot(contains('_activate(')));
    // Las acciones solo se ejecutan desde el botón.
    expect(page, contains('onPressed: onActivate'));
  });

  test('pending services say they must be activated and let the user decide', () {
    expect(page, contains('Pendiente. El GPS del teléfono está apagado.'));
    expect(page, contains('Se necesita activarlo para recibir viajes cercanos.'));
    expect(page, contains('Nada se activa solo'));
    expect(page, contains('Es opcional y depende de los permisos del teléfono.'));
  });

  test('the driver menu always offers the permissions page', () {
    expect(home, contains("import 'driver_permissions_page.dart';"));
    expect(home, contains("title: const Text('Permisos y servicios')"));
    expect(home, contains('DriverPermissionsPage('));
    final anchor = home.indexOf("title: const Text('Permisos y servicios')");
    expect(home.substring(anchor - 300, anchor), isNot(contains('if (overlayAllowed)')));
  });

  test('driver online checks the real location permission before server activation', () {
    expect(backgroundLocation, contains('Geolocator.checkPermission()'));
    expect(backgroundLocation, contains('LocationPermission.whileInUse'));
    expect(backgroundLocation, contains('Geolocator.requestPermission()'));
    expect(connected, contains('ensureDriverBackgroundLocation(context)'));
    expect(connected, contains('setDriverOnline(true'));
    expect(File('lib/location_service.dart').readAsStringSync(), contains('foregroundNotificationConfig: driverBackgroundTracking'));
    expect(home, contains('driverBackgroundTracking: true'));
    expect(connected, contains('driverBackgroundTracking: true'));
    expect(androidBuildScript, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
  });

  test('Android scaffold does not request restricted background location permission', () {
    expect(androidBuildScript, isNot(contains('android.permission.ACCESS_BACKGROUND_LOCATION')));
    expect(androidBuildScript, contains('if permission not in text'));
    expect(androidBuildScript, contains('for permission in (PERMISSION,)'));
  });
}

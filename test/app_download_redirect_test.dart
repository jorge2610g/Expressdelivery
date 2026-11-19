import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La página /app del QR redirige sola según el dispositivo, sin mostrar un panel.
void main() {
  late String page;

  setUpAll(() {
    page = File('web/app/index.html').readAsStringSync();
  });

  test('los accesos arrancan ocultos: no se muestra ningún panel de botones', () {
    expect(page, contains('<div id="links" class="links" hidden>'));
    expect(page, contains('Abriendo Express…'));
    expect(page, isNot(contains('Un solo QR para Android')));
  });

  test('el dispositivo se decide antes de consultar la configuración', () {
    final detect = page.indexOf('const isAndroid');
    final fetchConfig = page.indexOf("/rest/v1/app_download_links");
    expect(detect, greaterThan(0));
    expect(fetchConfig, greaterThan(detect));
  });

  test('Android va a su enlace; iPhone y web van a la web mientras no haya App Store', () {
    expect(page, contains("const platform = isAndroid ? 'android' : isIOS ? 'ios' : 'web';"));
    expect(page, contains("const target = usable(platform) ? platform : 'web';"));
    expect(page, contains('location.replace(links[target].url);'));
    expect(page, isNot(contains('La versión para iPhone todavía no está disponible.')));
  });

  test('los enlaces vienen del administrador y solo se aceptan https', () {
    expect(page, contains('app_download_links?select=platform,url,enabled'));
    expect(page, contains("parsed.protocol === 'https:'"));
  });

  test('si el navegador no deja salir, aparece un solo botón tras 4 segundos', () {
    expect(page, contains('show([target]);'));
    expect(page, contains('}, 4000);'));
  });
}

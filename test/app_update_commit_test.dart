import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la web avisa de cada versión nueva comparando el commit', () {
    final banner = File('lib/app_update_banner.dart').readAsStringSync();
    final main = File('lib/web_main.dart').readAsStringSync();
    final deploy = File('.github/workflows/deploy-web.yml').readAsStringSync();
    expect(banner, contains("remote['commit']"));
    expect(banner, contains('remoteCommit != widget.currentCommit'));
    expect(banner, contains('this.currentCommit'));
    expect(banner, contains('Duration(minutes: 2)'));
    expect(main, contains("String.fromEnvironment('EXPRESS_WEB_COMMIT')"));
    expect(main, contains('currentCommit: expressWebCommit'));
    expect(deploy, contains('EXPRESS_WEB_COMMIT=\${{ github.sha }}'));
  });

  test('la web no se recarga sola: el usuario pulsa Actualizar', () {
    final banner = File('lib/app_update_banner.dart').readAsStringSync();
    expect(banner, contains("child: const Text('Actualizar')"));
    expect(banner, contains('reloadExpressApp('));
  });
}

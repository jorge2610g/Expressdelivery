import 'package:expressdelivery/core/auth_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Express auth redirect', () {
    test('uses production Android package without native PackageInfo', () {
      expect(
        expressAuthRedirectUrl(
          isWeb: false,
          packageName: 'com.express.usuario1',
        ),
        'com.express.usuario1://login-callback/',
      );
    });

    test('uses Preview Android package without native PackageInfo', () {
      expect(
        expressAuthRedirectUrl(
          isWeb: false,
          packageName: 'com.express.usuario.preview',
        ),
        'com.express.usuario.preview://login-callback/',
      );
    });

    test('keeps canonical web redirect', () {
      expect(
        expressAuthRedirectUrl(isWeb: true),
        expressWebAuthRedirectUrl,
      );
    });
  });
}

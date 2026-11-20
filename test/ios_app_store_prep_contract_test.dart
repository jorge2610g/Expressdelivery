import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Preparación iOS para App Store. Fija decisiones que no deben cambiar sin
/// revisión: inicio con Apple en iOS, permisos declarados, sin ubicación en
/// segundo plano en iOS y ninguna subida a TestFlight sin orden explícita.
void main() {
  late String auth;
  late String script;
  late String workflow;
  late String entitlements;

  setUpAll(() {
    auth = File('lib/auth_entry.dart').readAsStringSync();
    script = File('.github/scripts/apply_ios_overlay.py').readAsStringSync();
    workflow = File('.github/workflows/build-ios.yml').readAsStringSync();
    entitlements =
        File('ios_overlay/Runner/Runner.entitlements').readAsStringSync();
  });

  test('el inicio con Apple se ofrece solo en iOS y junto a Google', () {
    expect(auth, contains('SignInWithAppleButton('));
    expect(
      auth,
      contains('defaultTargetPlatform == TargetPlatform.iOS) ...['),
    );
    expect(auth, contains('_googleAuthEnabled &&'));
  });

  test('el login con Apple usa signInWithIdToken con nonce', () {
    expect(auth, contains('provider: OAuthProvider.apple'));
    expect(auth, contains('nonce: rawNonce'));
    expect(auth, contains('nonce: expressAppleNonceHash(rawNonce)'));
    expect(auth, contains('AuthorizationErrorCode.canceled'));
  });

  test('el login con Apple completa el mismo control de acceso que el correo', () {
    final start = auth.indexOf('Future<void> _signInWithApple()');
    final end = auth.indexOf('Future<void> _clearLoginGuard()');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final body = auth.substring(start, end);
    expect(body, contains('_validateRuntimeAccess()'));
    expect(body, contains('_clearLoginGuard()'));
  });

  test('Info.plist declara permisos y el esquema de retorno del login', () {
    expect(script, contains('ITSAppUsesNonExemptEncryption'));
    expect(script, contains('NSCameraUsageDescription'));
    expect(script, contains('NSMicrophoneUsageDescription'));
    expect(script, contains('NSLocationWhenInUseUsageDescription'));
    expect(script, contains('NSPhotoLibraryUsageDescription'));
    expect(script, contains('CFBundleURLSchemes'));
    expect(script, contains("BUNDLE_ID = \"com.express.usuario1\""));
  });

  test('iOS no pide ubicación en segundo plano (decisión de primera versión)', () {
    expect(script, contains('BACKGROUND_MODES = ["remote-notification"]'));
    expect(script, isNot(contains('"location"')));
  });

  test('permission_handler recibe las definiciones de permisos en el Podfile', () {
    for (final definition in const [
      'PERMISSION_CAMERA=1',
      'PERMISSION_MICROPHONE=1',
      'PERMISSION_LOCATION=1',
      'PERMISSION_NOTIFICATIONS=1',
    ]) {
      expect(script, contains(definition));
    }
  });

  test('entitlements solo incluyen Sign in with Apple y push', () {
    expect(entitlements, contains('com.apple.developer.applesignin'));
    expect(entitlements, contains('aps-environment'));
    expect(entitlements, isNot(contains('com.apple.developer.associated-domains')));
  });

  test('el workflow iOS es manual y nunca se dispara por push', () {
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, isNot(contains('\non:\n  push:')));
    expect(workflow, isNot(contains('\n  push:')));
  });

  test('la subida a TestFlight requiere la casilla explícita', () {
    expect(workflow, contains('inputs.upload_testflight == true'));
    expect(workflow, contains('default: false'));
  });

  test('el workflow no imprime secretos', () {
    for (final line in workflow.split('\n')) {
      if (line.contains('echo') || line.contains('printf')) {
        expect(
          line.contains('PRIVATE_KEY') && !line.contains('> "\$KEY_FILE"'),
          isFalse,
          reason: 'no se debe imprimir la clave privada: $line',
        );
      }
    }
  });

  test('el manifiesto de privacidad existe, no rastrea y declara los datos', () {
    final manifest =
        File('ios_overlay/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
    expect(manifest, isNot(contains('<true/>\n\t<key>NSPrivacyTrackingDomains')));
    for (final type in const [
      'NSPrivacyCollectedDataTypeName',
      'NSPrivacyCollectedDataTypeEmailAddress',
      'NSPrivacyCollectedDataTypePhoneNumber',
      'NSPrivacyCollectedDataTypePreciseLocation',
      'NSPrivacyCollectedDataTypePhotosorVideos',
      'NSPrivacyCollectedDataTypeUserID',
      'NSPrivacyCollectedDataTypeDeviceID',
    ]) {
      expect(manifest, contains(type));
    }
    expect(manifest, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
  });

  test('el manifiesto se copia al proyecto y se registra en el target Runner', () {
    expect(script, contains('def copy_privacy_manifest()'));
    expect(script, contains('copy_privacy_manifest()\n    patch_pbxproj()'));
    final ruby =
        File('.github/scripts/add_ios_privacy_manifest.rb').readAsStringSync();
    expect(ruby, contains('resources_build_phase'));
    expect(ruby, contains("t.name == 'Runner'"));
    expect(workflow, contains('add_ios_privacy_manifest.rb'));
    // El registro va después del overlay y antes de compilar.
    expect(
      workflow.indexOf('apply_ios_overlay.py'),
      lessThan(workflow.indexOf('add_ios_privacy_manifest.rb')),
    );
    expect(
      workflow.indexOf('add_ios_privacy_manifest.rb'),
      lessThan(workflow.indexOf('flutter build ios')),
    );
  });

  test('el permiso de ubicación «siempre» se declara con texto honesto', () {
    // El plugin de ubicación referencia ese permiso en iOS; sin el texto,
    // App Store Connect rechaza la subida. La app no lo pide en iPhone.
    expect(script, contains('NSLocationAlwaysAndWhenInUseUsageDescription'));
    expect(script, contains('En iPhone no se sigue tu ubicación en segundo plano'));
    final background =
        File('lib/driver_background_location.dart').readAsStringSync();
    expect(
      background,
      contains('defaultTargetPlatform != TargetPlatform.android'),
      reason: 'el rastreo en segundo plano sigue siendo solo de Android',
    );
  });

  test('el número de build de iOS se puede fijar al lanzar el workflow', () {
    expect(workflow, contains('build_number:'));
    expect(workflow, contains('IOS_BUILD_NUMBER: \${{ inputs.build_number }}'));
    expect(workflow, contains('--build-number="\$IOS_BUILD_NUMBER"'));
  });
}

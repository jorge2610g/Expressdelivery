import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google Mobile Ads dependency and loaders stay removed', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final mobile = File('lib/mobile_main.dart').readAsStringSync();
    final passenger = File('lib/video_style_home.dart').readAsStringSync();

    expect(pubspec, isNot(contains('google_mobile_ads')));
    expect(mobile, isNot(contains('ExpressPassengerAds')));
    // Los anuncios propios (Supabase, sin SDK) sí pueden existir; lo que se
    // prohíbe es el SDK de AdMob y sus archivos de verificación.
    final own = File('lib/passenger_ads.dart').readAsStringSync();
    expect(own, isNot(contains('google_mobile_ads')));
    expect(passenger, isNot(contains('google_mobile_ads')));
    expect(File('lib/passenger_ads_mobile.dart').existsSync(), isFalse);
    expect(File('web/app-ads.txt').existsSync(), isFalse);
  });

  test('Android build cannot reintroduce AdMob or advertising permission', () {
    final workflow =
        File('.github/workflows/build-android.yml').readAsStringSync();
    final branding =
        File('.github/scripts/prepare_android_branding.py').readAsStringSync();
    expect(workflow, contains('Android ads policy verified'));
    expect(workflow, isNot(contains('ADMOB_ANDROID_APP_ID')));
    expect(workflow, isNot(contains('ADMOB_PASSENGER_BANNER_UNIT_ID')));
    expect(branding, isNot(contains('ca-app-pub-')));
    expect(branding, contains('tools:node="remove"'));
    expect(branding, contains('com.google.android.gms.permission.AD_ID'));
  });
}

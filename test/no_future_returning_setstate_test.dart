import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('driver refresh setState callback never returns a Future', () {
    final source = File('lib/video_style_home.dart').readAsStringSync();

    // An expression body such as "setState(() => driverFuture = nextFuture)"
    // returns Future<_DriverStateData>, which Flutter rejects at runtime.
    expect(
      RegExp(r'setState\s*\(\s*\(\)\s*=>\s*driverFuture\s*=')
          .hasMatch(source),
      isFalse,
    );
    expect(
      RegExp(r'setState\s*\(\s*\(\)\s*\{\s*driverFuture\s*=\s*nextFuture;\s*\}\s*\)')
          .hasMatch(source),
      isTrue,
    );
  });

  test('banner refresh setState callback never returns a Future', () {
    final source = File('lib/connected_experience.dart').readAsStringSync();
    expect(
      RegExp(r'setState\s*\(\s*\(\)\s*=>\s*bannersFuture\s*=')
          .hasMatch(source),
      isFalse,
    );
  });
}

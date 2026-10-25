import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'landing waits on a home placeholder instead of opening the Trips map',
    () {
      final source = File('lib/connected_experience.dart').readAsStringSync();
      final entryStart = source.indexOf('Widget _passengerEntryPage()');
      final loadingPageStart = source.indexOf(
        'class _PassengerLandingLoadingPage',
      );

      expect(entryStart, greaterThanOrEqualTo(0));
      expect(loadingPageStart, greaterThan(entryStart));

      final entry = source.substring(entryStart, loadingPageStart);
      expect(entry, contains('ConnectionState.waiting'));
      expect(entry, contains('return _PassengerLandingLoadingPage('));
      expect(entry, isNot(contains("return _passengerModulePage('ride')")));
    },
  );
}

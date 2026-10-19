import 'dart:io';

import 'package:expressdelivery/pickup_wait_countdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 10, 17, 12);

  group('pickup wait countdown', () {
    test('counts down from the server start mark', () {
      expect(
        pickupWaitRemainingSeconds(
          start: start,
          now: start.add(const Duration(seconds: 1)),
        ),
        299,
      );
      expect(pickupWaitClock(299), '4:59');
    });

    test('never invents a full 5:00 when the server mark is missing', () {
      expect(
        pickupWaitRemainingSeconds(start: null, now: start),
        isNull,
      );
    });

    test('a missing mark after a known one keeps the real remaining time', () {
      final effective = effectivePickupWaitStart(
        serverStart: null,
        lastKnownStart: start,
      );
      final now = start.add(const Duration(seconds: 61));

      expect(pickupWaitRemainingSeconds(start: effective, now: now), 239);
      expect(pickupWaitClock(239), '3:59');
    });

    test('a fresh server mark takes precedence over the remembered one', () {
      final newer = start.add(const Duration(seconds: 100));
      final effective = effectivePickupWaitStart(
        serverStart: newer,
        lastKnownStart: start,
      );

      expect(effective, newer);
    });

    test('expires at zero and stays there', () {
      expect(
        pickupWaitRemainingSeconds(
          start: start,
          now: start.add(const Duration(minutes: 9)),
        ),
        0,
      );
      expect(pickupWaitClock(0), '0:00');
    });

    test('parses the server string in UTC and rejects garbage', () {
      expect(parsePickupWaitStart('2026-10-17T12:00:00Z'), start);
      expect(parsePickupWaitStart(null), isNull);
      expect(parsePickupWaitStart('no es una fecha'), isNull);
    });
  });

  group('pickup wait widgets use the shared rule', () {
    late String home;

    setUpAll(() {
      home = File('lib/video_style_home.dart').readAsStringSync();
    });

    test('no fixed 5:00 fallback and no mount-time fallback clock', () {
      expect(home, isNot(contains("if (since == null) return '5:00';")));
      expect(home, isNot(contains('fallbackStart')));
    });

    test('PIN entry placeholder is not four zeros', () {
      expect(home, isNot(contains("hintText: '0000'")));
      expect(home, contains('helperMaxLines: 2'));
    });

    test('both widgets import the shared countdown', () {
      expect(
        home,
        contains("import 'pickup_wait_countdown.dart';"),
      );
      expect(
        home,
        contains('pickupWaitRemainingSeconds('),
      );
    });
  });
}

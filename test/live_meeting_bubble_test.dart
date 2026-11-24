import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/live_meeting_bubble.dart';

void main() {
  test('solo abre enlaces https de Google Meet', () {
    expect(liveMeetingUrlAllowed('https://meet.google.com/abc-defg-hij'), isTrue);
    expect(liveMeetingUrlAllowed('http://meet.google.com/abc'), isFalse);
    expect(liveMeetingUrlAllowed('https://evil.com/meet.google.com'), isFalse);
    expect(liveMeetingUrlAllowed('javascript:alert(1)'), isFalse);
  });

  test('texto de «empezó hace»', () {
    expect(liveMeetingStartedText(0), 'Acaba de empezar');
    expect(liveMeetingStartedText(4), 'Empezó hace 4 min');
    expect(liveMeetingStartedText(125), 'Empezó hace 2 h');
    final now = DateTime(2026, 11, 24, 20, 0);
    expect(
      liveMeetingMinutesSince(
          now.subtract(const Duration(minutes: 7)).toIso8601String(), now),
      7,
    );
  });

  test('el círculo envuelve la pantalla del conductor y del pasajero', () {
    final src = File('lib/connected_experience.dart').readAsStringSync();
    expect(src, contains('LiveMeetingOverlay('));
  });
}

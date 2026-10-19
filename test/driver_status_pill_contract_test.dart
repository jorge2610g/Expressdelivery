import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('driver pill stays connected during an active service', () {
    final source = File('lib/video_style_home.dart').readAsStringSync();
    final start = source.indexOf('online: hasActiveDriverService');
    expect(start, isNonNegative, reason: 'header badge input not found');
    final window = source.substring(start, start + 400);
    // The server keeps an active driver in 'busy'. The label must read
    // "En servicio", not "Fuera de línea", so 'busy' has to count as online.
    expect(window, contains("== 'busy'"));
    expect(window, isNot(contains('? false')));
  });
}

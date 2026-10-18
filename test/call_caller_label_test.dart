import 'dart:io';

import 'package:expressdelivery/call_caller_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('callerDisplayName', () {
    test('keeps a real person name, including accents and ñ', () {
      expect(callerDisplayName('María Pérez'), 'María Pérez');
      expect(callerDisplayName('Ñuñez'), 'Ñuñez');
      expect(callerDisplayName('Juan-Carlos O\'Brien'), "Juan-Carlos O'Brien");
    });

    test('collapses spaces around the name', () {
      expect(callerDisplayName('  Ana   López  '), 'Ana López');
    });

    test('template markers never reach the call screen', () {
      expect(callerDisplayName('%0'), kCallerFallbackLabel);
      expect(callerDisplayName('%0/0%/xo'), kCallerFallbackLabel);
      expect(callerDisplayName('hola %0 mundo'), kCallerFallbackLabel);
    });

    test('empty, missing and very long values use the fallback', () {
      expect(callerDisplayName(null), kCallerFallbackLabel);
      expect(callerDisplayName('   '), kCallerFallbackLabel);
      expect(callerDisplayName('a' * 61), kCallerFallbackLabel);
    });

    test('values with digits or symbols that are not names use the fallback', () {
      expect(callerDisplayName('user_12345'), kCallerFallbackLabel);
      expect(callerDisplayName('<b>x</b>'), kCallerFallbackLabel);
      expect(callerDisplayName('Ana123'), kCallerFallbackLabel);
    });

    test('a custom fallback is honored', () {
      expect(callerDisplayName(null, fallback: 'Un pasajero'), 'Un pasajero');
    });
  });

  test('the voice call screen uses the sanitized name', () {
    final call = File('lib/private_voice_call.dart').readAsStringSync();
    expect(call, contains("import 'call_caller_label.dart';"));
    expect(call, isNot(contains("result['userName']?.toString() ?? 'Express'")));
    expect(call, contains("callerDisplayName(result['userName']?.toString())"));
  });
}

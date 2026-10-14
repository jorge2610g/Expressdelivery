import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Token04 nonce follows ZEGO official nonnegative Int31 range', () {
    final source = File('supabase/functions/zego-call/index.ts')
        .readAsStringSync();
    final start = source.indexOf('async function generateToken04(');
    final end = source.indexOf('async function userSummary(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final generator = source.substring(start, end);
    // Official ZEGOCLOUD token04 uses rand.Int31(): signed, but never negative.
    // Using crypto.getRandomValues(Int32Array) generated a negative nonce
    // for about half of the tokens and may cause ZIM 50131 login failures.
    expect(generator, contains('new Uint32Array(1)'));
    expect(generator, contains('nonceArray[0] & 0x7fffffff'));
    expect(generator, isNot(contains('new Int32Array(1)')));
    // Never ship app secrets or sign Token04 in the Flutter/Web client.
    expect(generator, contains("Deno.env"));
  });
}

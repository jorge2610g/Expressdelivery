import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed and cancelled voice invitations never trigger the 30s lock', () {
    final source = File('supabase/functions/zego-call/index.ts')
        .readAsStringSync();
    expect(source, contains(".not('status', 'in', '(failed,cancelled)')"));
    // An active trip and the participant identity must still be validated.
    expect(source, contains('resolveActiveTrip(admin, tripId, user.id, channel)'));
    expect(source, contains('enforceCallCooldown(admin, trip.id, user.id)'));
    // Token generation must happen before creating a cooldown row.
    final section = source.substring(source.indexOf("if (action === 'prepare')"),
        source.indexOf("if (action === 'event')"));
    expect(section.indexOf('await issueToken(user.id)'),
        lessThan(section.indexOf('.insert({')));
  });
}

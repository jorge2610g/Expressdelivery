import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_online_sequence.dart';

void main() {
  test('waits for GPS persistence before marking driver online', () async {
    final saved = Completer<void>();
    final events = <String>[];
    final connecting = saveDriverGpsThenConnect(
      savePosition: () {
        events.add('start gps');
        return saved.future;
      },
      setOnline: () async { events.add('online'); },
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, ['start gps']);
    saved.complete();
    await connecting;
    expect(events, ['start gps', 'online']);
  });

  test('failed GPS write never activates dispatch', () async {
    var switchedOnline = false;
    await expectLater(
      saveDriverGpsThenConnect(
        savePosition: () async => throw StateError('GPS failed'),
        setOnline: () async { switchedOnline = true; },
      ),
      throwsStateError,
    );
    expect(switchedOnline, isFalse);
  });
}

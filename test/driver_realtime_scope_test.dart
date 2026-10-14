import 'dart:io';

import 'package:expressdelivery/driver_realtime_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('avoids driver home refresh for other zones', () {
    expect(expressDriverRealtimeShouldRefresh(
      record: {'zone_id': 'iquique', 'channel':'production'},
      zoneId:'trinidad', channel:'production',
    ), isFalse);
  });
  test('avoids refresh for other account runtime channels', () {
    expect(expressDriverRealtimeShouldRefresh(
      record: {'zone_id': 'iquique', 'channel':'preview'},
      zoneId:'iquique', channel:'production',
    ), isFalse);
  });
  test('keeps refreshes for matching zone and channel', () {
    expect(expressDriverRealtimeShouldRefresh(
      record: {'zone_id': 'iquique', 'channel':'preview'},
      zoneId:'iquique', channel:'preview',
    ), isTrue);
  });
  test('missing legacy metadata does not hide events', () {
    expect(expressDriverRealtimeShouldRefresh(
      record: {}, zoneId:'iquique', channel:'production',
    ), isTrue);
    expect(expressDriverRealtimeShouldRefresh(
      record: {'zone_id': 'iquique'}, zoneId:null, channel:'production',
    ), isTrue);
  });
  test('scope applies to all three driver realtime sources', () {
    final src=File('lib/video_style_home.dart').readAsStringSync();
    final start=src.indexOf("table: 'ride_requests',");
    final end=src.indexOf("void _refreshDriverHome()", start);
    final callbacks=src.substring(start,end);
    expect(RegExp('expressDriverRealtimeShouldRefresh\\(')
        .allMatches(callbacks).length, 3);
    expect(callbacks, contains("channel: ExpressRuntimeChannel.name"));
    expect(callbacks, contains("cachedData?.profile['zone_id']"));
  });
}

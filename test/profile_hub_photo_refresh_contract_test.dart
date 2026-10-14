import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Profile screen fetches data once per explicit refresh, not each frame', () {
    final source = File('lib/express_account_pages.dart').readAsStringSync();
    final start = source.indexOf('class _ExpressProfileHubPageState');
    final next = source.indexOf('\nclass ', start + 15);
    expect(start, greaterThanOrEqualTo(0));
    final section = source.substring(start, next >= 0 ? next : source.length);
    expect(section, contains('late Future<_ProfileBundle> _profileFuture;'));
    expect(section, contains('_profileFuture = _load();'));
    expect(section, contains('future: _profileFuture'));
    expect(section, isNot(contains('future: _load(),')));
    expect(section, contains('onChanged: _refreshProfile'));
    expect(section, contains('void _refreshProfile()'));
    expect(section, contains('didUpdateWidget(ExpressProfileHubPage oldWidget)'));
  });
}

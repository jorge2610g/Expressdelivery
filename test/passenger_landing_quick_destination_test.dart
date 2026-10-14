import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('landing quick actions select destination, not just the module', () {
    final landing = File('lib/connected_experience.dart').readAsStringSync();
    expect(landing, contains("onTap: () => onQuickDestination('ride')"));
    expect(landing, contains("onTap: () => onQuickDestination('delivery')"));
    expect(landing, contains('quickDestinationOnEntry = true;'));
    expect(landing, contains('openDestinationPickerOnStart: quickDestinationOnEntry'));
    expect(landing, contains('quickDestinationOnEntry = false;'));
    // Cards above the quick actions retain their regular module navigation.
    expect(landing, contains('onTap: () => onSelect(key)'));
  });

  test('both quick actions reuse the actual passenger destination picker', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains('openDestinationPickerOnStart'));
    expect(home, contains('unawaited(_pickDestination())'));
    expect(home, contains("title: serviceType == 'delivery'"));
    expect(home, contains("'Dirección de entrega'"));
    expect(home, contains("'¿A dónde vas?'"));
    // Do not create a parallel ride or delivery request from the landing.
    expect(home, contains('destination = result;'));
  });
}

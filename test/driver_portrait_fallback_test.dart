import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_portrait.dart';

void main() {
  test('never displays previous avatar before the authorized new photo', () {
    expect(
      driverPortraitFallback('driver/profile/current.jpg',
          'https://example.com/previous.jpg'),
      isNull,
    );
  });

  test('allows fallback only when authorized photo is missing', () {
    expect(driverPortraitFallback(null, 'https://example.com/image.jpg'),
        'https://example.com/image.jpg');
    expect(driverPortraitFallback(null, ''), isNull);
  });
}

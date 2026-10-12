import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_portrait.dart';

void main() {
  test('reads the authorized portrait path for the offer driver only', () {
    const driver = '00000000-0000-0000-0000-000000000001';
    expect(authorizedOfferPortraitPath({
      'driver_id': driver,
      'driver_profiles': {
        'profile_photo_path': '$driver/profile/photo.jpg',
      },
    }), '$driver/profile/photo.jpg');
  });

  test('never displays a different driver portrait or raw avatar link', () {
    const driver = '00000000-0000-0000-0000-000000000001';
    expect(authorizedOfferPortraitPath({
      'driver_id': driver,
      'driver_profiles': {
        'profile_photo_path': 'another-driver/photo.jpg',
      },
    }), isNull);
    expect(authorizedOfferPortraitPath({
      'driver_id': driver,
      'driver_user': {'avatar_url': 'https://example.com/photo.jpg'},
    }), isNull);
  });
}

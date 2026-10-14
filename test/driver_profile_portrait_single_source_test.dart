import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_portrait.dart';

void main() {
  const photo = 'https://cdn.example.test/public-photo.jpg';
  const profile = 'driver-1/profile/official-photo.jpg';

  test('one secure driver portrait never flashes a second public photo', () {
    expect(showPublicAvatarForDriverPortrait(
      fallbackUrl: photo, driverId: 'driver-1', approvedPath: profile,
      privateLookupComplete: false, privatePathFound: false,
    ), isFalse);
    expect(showPublicAvatarForDriverPortrait(
      fallbackUrl: photo, driverId: 'driver-1', approvedPath: profile,
      privateLookupComplete: true, privatePathFound: true,
    ), isFalse);
  });

  test('do not show public portrait while authorized RPC is pending', () {
    expect(showPublicAvatarForDriverPortrait(
      fallbackUrl: photo, driverId: 'driver-1', approvedPath: null,
      privateLookupComplete: false, privatePathFound: false,
    ), isFalse);
  });

  test('public photo remains a fallback when no private image exists', () {
    expect(showPublicAvatarForDriverPortrait(
      fallbackUrl: photo, driverId: 'driver-1', approvedPath: null,
      privateLookupComplete: true, privatePathFound: false,
    ), isTrue);
    expect(showPublicAvatarForDriverPortrait(
      fallbackUrl: photo, driverId: null, approvedPath: null,
      privateLookupComplete: false, privatePathFound: false,
    ), isTrue);
  });

  test('once a private path is located never show another image if download fails', () {
    expect(showPublicAvatarForDriverPortrait(
      fallbackUrl: photo, driverId: 'driver-1', approvedPath: null,
      privateLookupComplete: true, privatePathFound: true,
    ), isFalse);
  });

  test('empty public URL does not produce an alternative profile photo', () {
    expect(showPublicAvatarForDriverPortrait(
      fallbackUrl: ' ', driverId: null, approvedPath: null,
      privateLookupComplete: true, privatePathFound: false,
    ), isFalse);
  });
}

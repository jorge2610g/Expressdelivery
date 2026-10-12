import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_portrait.dart';

void main() {
  const driver='00000000-0000-0000-0000-000000000007';
  test('enriched avatar arrives after first bare realtime offer', () {
    final bare={'id':'offer-1','driver_id':driver,'proposed_fare':1500};
    final enriched={...bare,'driver_profiles':{
      'profile_photo_path':'$driver/face.jpg'
    }};
    expect(authorizedOfferPortraitPath(bare),isNull);
    expect(authorizedOfferPortraitPath(
      refreshedPassengerOffer(bare,enriched),
    ),'$driver/face.jpg');
  });
  test('later bare realtime update does not erase authorized enrichment', () {
    final enriched={'id':'offer-1','driver_id':driver,
      'driver_profiles':{'profile_photo_path':'$driver/face.jpg'},
      'driver_user':{'full_name':'Conductor'}};
    final bare={'id':'offer-1','driver_id':driver,'status':'pending'};
    final merged=refreshedPassengerOffer(enriched,bare);
    expect(authorizedOfferPortraitPath(merged),'$driver/face.jpg');
    expect((merged['driver_user'] as Map)['full_name'],'Conductor');
  });
  test('explicit revoked server path is not retained', () {
    final enriched={'id':'offer-1','driver_id':driver,
      'driver_profiles':{'profile_photo_path':'$driver/face.jpg'}};
    final revoked={'id':'offer-1','driver_id':driver,
      'driver_profiles':{'profile_photo_path':null}};
    expect(authorizedOfferPortraitPath(
      refreshedPassengerOffer(enriched,revoked)),isNull);
  });
}

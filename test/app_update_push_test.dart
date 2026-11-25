import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/app_update_push.dart';

void main() {
  test('build objetivo del deep_link', () {
    expect(appUpdateTargetBuild('app_update/179'), 179);
    expect(appUpdateTargetBuild('avisos/abc'), isNull);
    expect(appUpdateTargetBuild(null), isNull);
    expect(appUpdateTargetBuild('app_update/xx'), isNull);
  });

  test('solo va a la tienda si la versión instalada es anterior', () {
    expect(appUpdateNeedsStore(178, 179), isTrue);
    expect(appUpdateNeedsStore(179, 179), isFalse);
    expect(appUpdateNeedsStore(180, 179), isFalse);
    expect(appUpdateNeedsStore(0, 179), isFalse);
  });

  test('la tienda es el paquete oficial', () {
    expect(expressPlayStoreUrl, endsWith('id=com.express.usuario1'));
  });
}

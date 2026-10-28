import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Moto presentation fits official Flutter widgets into narrow phone frames', () {
    final entry = File('lib/presentation_moto_web.dart').readAsStringSync();
    expect(entry, contains('const referenceWidth=414.0;'));
    expect(entry, contains('logicalWidth=viewportWidth<referenceWidth'));
    expect(entry, contains('logicalHeight=viewportHeight*(logicalWidth/viewportWidth)'));
    expect(entry, contains('fit:BoxFit.contain'));
    expect(entry, contains('child:ExpressMotoPresentationPhone('));

    final widgets=File('lib/express_moto_demo_widgets.dart').readAsStringSync();
    expect(widgets, contains('fit:BoxFit.scaleDown,alignment:Alignment.centerLeft'));
    expect(widgets, contains('maxLines:1,softWrap:false'));
    expect(widgets, contains('EdgeInsets.fromLTRB(12,29,12,7)'));

    final html=File('web/presentacion/index.html').readAsStringSync();
    expect(html, contains('src="./flutter/?role=pasajero&v='));
    expect(html, contains('src="./flutter/?role=conductor&v='));
    expect(html, contains('id="driverPinInput"'));
    expect(html, contains("onAction('pin-verified')"));
  });
}

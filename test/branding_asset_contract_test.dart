import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checked-in Express logo matches the verified canonical PNG source', () {
    final source = File('assets/branding/express_app_icon_512.b64');
    final icon = File('assets/branding/express_app_icon.png');
    final expected = base64.decode(
      source.readAsStringSync().replaceAll(RegExp(r'\s+'), ''),
    );

    expect(icon.readAsBytesSync(), expected);
  });
}

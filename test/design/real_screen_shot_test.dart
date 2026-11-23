import 'dart:io';
import 'dart:typed_data';

import 'package:expressdelivery/auth_entry.dart';
import 'package:expressdelivery/design/express_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _fonts() async {
  const root = '/root/flutter-sdk/flutter/bin/cache/artifacts/material_fonts';
  Future<ByteData> r(String n) async =>
      ByteData.view(Uint8List.fromList(await File('$root/$n').readAsBytes()).buffer);
  final f = FontLoader('Roboto')
    ..addFont(r('Roboto-Regular.ttf'))
    ..addFont(r('Roboto-Medium.ttf'))
    ..addFont(r('Roboto-Bold.ttf'));
  await f.load();
  final i = FontLoader('MaterialIcons')..addFont(r('MaterialIcons-Regular.otf'));
  await i.load();
}

/// Capturas de diseño: solo se generan a pedido (EXPRESS_GOLDEN=1), porque
/// dependen de las fuentes del SDK local.
final bool _skipShots = Platform.environment['EXPRESS_GOLDEN'] != '1';

void main() {
  if (_skipShots) return;
  setUpAll(() async {
    await _fonts();
    ExpressType.family = 'Roboto';
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:1', anonKey: 'x');
  });
  testWidgets('real · acceso', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ExpressTheme.light(),
      home: const ExpressAuthPage(),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/real_01_acceso.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:expressdelivery/design/express_tokens.dart';
import 'package:expressdelivery/restaurant_shell.dart';
import 'package:expressdelivery/services/express_service.dart';
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

/// Capturas del portal de restaurantes; solo con EXPRESS_GOLDEN=1.
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
  final access = <Map<String, dynamic>>[
    {'merchant_id': 'm1', 'merchant_name': 'Go Pollos Rhosse'}
  ];
  final state = <String, dynamic>{
    'role': 'owner',
    'currency': 'BOB',
    'merchant': {
      'open_override': true,
      'rating': 4.8,
      'description': 'Pollo a la leña y hamburguesas',
      'category_key': 'Pollo asado',
      'address': 'Av. Cipriano Barace, Trinidad',
      'minimum_order': 20,
      'delivery_fee': 8,
      'eta_min_minutes': 20,
      'eta_max_minutes': 35,
    },
    'stats': {'orders': 42, 'sales_products': 1860},
  };
  final orders = <Map<String, dynamic>>[
    {'id': 'a1b2c3d4-0000', 'status': 'awaiting_merchant', 'total_amount': 48, 'currency_code': 'BOB'},
    {'id': 'e5f6a7b8-0000', 'status': 'preparing', 'total_amount': 27, 'currency_code': 'BOB'},
    {'id': 'c9d0e1f2-0000', 'status': 'delivering', 'total_amount': 65, 'currency_code': 'BOB'},
  ];
  for (final (name, size, section) in [
    ('inicio_escritorio', const Size(1280, 800), RestaurantSection.home),
    ('perfil_escritorio', const Size(1280, 800), RestaurantSection.profile),
    ('inicio_movil', const Size(390, 800), RestaurantSection.home),
  ]) {
    testWidgets('portal restaurantes · $name', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ExpressTheme.light(),
        home: RestaurantPortalShell(
          service: ExpressService(),
          access: access,
          onLogout: () async {},
          debugState: state,
          debugOrders: orders,
          debugSection: section,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/restaurante_$name.png'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  }
}

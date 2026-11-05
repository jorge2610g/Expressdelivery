import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261105100000_passenger_ads_placements.sql',
  ).readAsStringSync();
  final app = File('lib/video_style_home.dart').readAsStringSync();
  final service = File('lib/services/express_service.dart').readAsStringSync();

  test('los lugares de la app coinciden con la validación de Supabase', () {
    const placements = ['home_landing', 'map_home', 'ride_chooser'];
    for (final placement in placements) {
      expect(migration, contains("'$placement'"));
    }
    expect(
      migration,
      contains(
        "array['home_landing','map_home','ride_chooser']::text[]",
      ),
    );
    expect(app, contains("placement: 'map_home'"));
    expect(app, contains("placement: 'ride_chooser'"));
  });

  test('la app llama a la función de lectura por lugar', () {
    expect(service, contains("'passenger_ads_v1'"));
    expect(service, contains("'p_placement': placement"));
    expect(
      migration,
      contains('create or replace function public.passenger_ads_v1('),
    );
    expect(migration, contains('p_placement = any(b.placements)'));
  });
}

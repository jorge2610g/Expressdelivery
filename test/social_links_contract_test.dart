import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: 'No se encontró $signature');
  final next = source.indexOf('\n  void _', start + signature.length);
  return next == -1 ? source.substring(start) : source.substring(start, next);
}

void main() {
  final home = File('lib/video_style_home.dart').readAsStringSync();
  final widget = File('lib/social_links.dart').readAsStringSync();
  final migration = File(
    'supabase/migrations/20261107120000_app_social_links.sql',
  ).readAsStringSync();

  test('el menú del pasajero muestra las redes junto al logo Express', () {
    final body = _methodBody(home, 'void _showPassengerMenu()');
    expect(body, contains("trailing: ExpressSocialLinksRow(audience: 'passenger')"));
    expect(body, contains('ExpressOfficialLogo(size: 48, radius: 15)'));
  });

  test('el menú del conductor muestra las redes en su cabecera', () {
    final body = _methodBody(home, 'void _showDriverMenu()');
    expect(body, contains("trailing: ExpressSocialLinksRow(audience: 'driver')"));
    expect(body, contains("'Modo Conductor'"));
  });

  test('el widget carga la RPC pública y no rompe el menú si falla', () {
    expect(widget, contains("supabase\n        .rpc('app_social_links_public_v1')"));
    expect(widget, contains('launchUrl('));
    expect(widget, contains('LaunchMode.externalApplication'));
    expect(widget, contains('No se pudo abrir el enlace'));
    expect(widget, contains("label: network.label"));
    expect(widget, contains('SizedBox.shrink()'));
  });

  test('la migración define tabla, RPC públicas y de super admin', () {
    expect(migration, contains('create table if not exists public.app_social_links'));
    expect(migration, contains('enable row level security'));
    expect(migration, contains('function public.app_social_links_public_v1()'));
    expect(migration, contains('function public.admin_app_social_links_list_v1()'));
    expect(
      migration,
      contains('function public.admin_app_social_links_save_v1('),
    );
    expect(migration, contains("public.admin_operator_assert_module('dashboard')"));
    expect(migration, contains("'save_social_link'"));
    expect(migration, contains("grant execute on function public.app_social_links_public_v1() to anon, authenticated"));
  });
}

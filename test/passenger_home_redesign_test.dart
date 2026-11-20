import 'dart:io';

import 'package:expressdelivery/passenger_home_redesign.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('accesos directos', () {
    test('Casa y Trabajo siempre están; sin guardar abren «Lugares guardados»', () {
      var manage = 0;
      final items = passengerShortcutsFrom(
        saved: const [],
        onSaved: (_) => fail('no hay lugar guardado'),
        onManage: () => manage++,
      );
      expect(items.map((e) => e.label), ['Casa', 'Trabajo']);
      items[0].onTap();
      items[1].onTap();
      expect(manage, 2);
    });

    test('con lugares guardados eligen ese lugar como destino', () {
      final home = {'label': 'Casa', 'latitude': -14.8, 'longitude': -64.9};
      final work = {'label': ' trabajo ', 'latitude': -14.9, 'longitude': -65.0};
      Map<String, dynamic>? picked;
      final items = passengerShortcutsFrom(
        saved: [home, work],
        onSaved: (row) => picked = row,
        onManage: () => fail('hay lugar guardado'),
      );
      items[0].onTap();
      expect(picked, home);
      items[1].onTap();
      expect(picked, work);
    });

    test('suma otros lugares sin repetir Casa ni Trabajo y con tope', () {
      final saved = <Map<String, dynamic>>[
        {'label': 'Casa'},
        {'label': 'Mamá'},
        {'label': 'Gimnasio'},
        {'label': 'Oficina'},
        {'label': 'Banco'},
        {'label': ''},
      ];
      final items = passengerShortcutsFrom(
        saved: saved,
        onSaved: (_) {},
        onManage: () {},
      );
      expect(items.map((e) => e.label), [
        'Casa',
        'Trabajo',
        'Mamá',
        'Gimnasio',
        'Oficina',
      ]);
    });
  });

  group('píldora de búsqueda', () {
    testWidgets('la barra abre el buscador y la mira abre el selector', (
      tester,
    ) async {
      var search = 0;
      var map = 0;
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 360,
            child: PassengerHomePill(
              subtitle: 'Trinidad · 3 vehículos cerca',
              onSearch: () => search++,
              onPickOnMap: () => map++,
            ),
          ),
        ),
      );
      expect(find.text('¿A dónde vamos?'), findsOneWidget);
      expect(find.text('Trinidad · 3 vehículos cerca'), findsOneWidget);

      await tester.tap(find.text('¿A dónde vamos?'));
      expect(search, 1);
      expect(map, 0);

      await tester.tap(find.byTooltip('Elegir moviendo el mapa'));
      expect(map, 1);
      expect(search, 1);
    });

    testWidgets('mide al menos 48 px en cada botón', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 360,
            child: PassengerHomePill(
              subtitle: 'x',
              onSearch: () {},
              onPickOnMap: () {},
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byTooltip('Elegir moviendo el mapa'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('chips y costado', () {
    testWidgets('los chips responden y «Ver todos» abre guardados', (
      tester,
    ) async {
      var casa = 0;
      var manage = 0;
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 360,
            child: PassengerShortcutChips(
              items: [
                PassengerShortcut(
                  label: 'Casa',
                  icon: Icons.home_outlined,
                  onTap: () => casa++,
                ),
              ],
              onManage: () => manage++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Casa'));
      await tester.tap(find.text('Ver todos'));
      expect(casa, 1);
      expect(manage, 1);
    });

    testWidgets('el costado abre el menú y ubica; mientras ubica no repite', (
      tester,
    ) async {
      var menu = 0;
      var locate = 0;
      Widget rail({required bool locating}) => _app(
        PassengerSideRail(
          onMenu: () => menu++,
          onLocate: () => locate++,
          locating: locating,
        ),
      );
      await tester.pumpWidget(rail(locating: false));
      await tester.tap(find.byTooltip('Menú'));
      await tester.tap(find.byTooltip('Mi ubicación'));
      expect(menu, 1);
      expect(locate, 1);

      await tester.pumpWidget(rail(locating: true));
      await tester.tap(find.byTooltip('Mi ubicación'));
      expect(locate, 1, reason: 'no repite mientras ubica');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  test('el inicio nuevo solo se activa en cuentas de Prueba y sin servicio', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains("import 'passenger_home_redesign.dart';"));
    final start = home.indexOf('final idleNewHome =');
    expect(start, greaterThan(0));
    final block = home.substring(start, start + 400);
    expect(block, contains('ExpressRuntimeChannel.previewMode'));
    expect(block, contains('!rawPassengerFlowActive'));
    expect(block, contains('data.pendingRating == null'));
    expect(home, contains('newHome: ExpressRuntimeChannel.previewMode'));
    // El menú y la búsqueda de siempre siguen cuando no es inicio nuevo.
    expect(home, contains('if (effectivePassengerOffers.isEmpty && !idleNewHome)'));
    expect(home, contains('_showPassengerMenu'));
  });
}

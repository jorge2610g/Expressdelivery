import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('out-of-coverage home keeps app navigation and gates only service taps', () {
    final source = File('lib/connected_experience.dart').readAsStringSync();
    expect(source, contains('modules: _coverageUnavailableModules'));
    expect(source, contains('onSelect: showNotice'));
    expect(source, contains('onQuickDestination: showNotice'));
    expect(source, contains('Puedes seguir usando la app. La cobertura se revisa'));
    expect(source, contains("'module_key': 'ride'"));
    expect(source, contains("'module_key': 'delivery'"));
    expect(source, contains("'module_key': 'market'"));
    expect(source, contains('Aún no hay cobertura en esta zona'));
    expect(source, isNot(contains('return _PassengerUnavailableArea(')));
  });

  test('landing cards use responsive illustrated carousel rather than fixed icons', () {
    final source = File('lib/connected_experience.dart').readAsStringSync();
    expect(source, contains('ListView.separated('));
    expect(source, contains('ExpressLandingArtwork(kind: key'));
    expect(source, isNot(contains('height: modules.length == 1 ? 150 : 158')));
    expect(source, isNot(contains(
      'Los servicios de esta pantalla dependen de la zona y de lo que administración tenga habilitado.',
    )));
  });

  test('no user-visible administrative instructions remain in known screens', () {
    const banned = <String>[
      'El administrador tiene habilitado',
      'métodos habilitados por administración',
      'El administrador debe aprobar tu perfil',
      'Un administrador revisará tu información',
      'Un administrador revisará tu fotografía',
      'Solo el administrador puede aprobarlos',
      'Solicitud enviada al administrador',
      'Administración todavía no habilitó',
      'Administración tiene las suscripciones',
      'El administrador puede mantener',
      'Pago verificado por administración',
    ];
    final sources = <String>[
      'lib/connected_experience.dart',
      'lib/video_style_home.dart',
      'lib/express_account_pages.dart',
      'lib/driver_setup.dart',
      'lib/driver_kyc_correction_page.dart',
      'lib/driver_manual_identity_capture.dart',
      'lib/driver_subscription_page.dart',
      'lib/driver_work_permissions_page.dart',
      'lib/driver_championship_page.dart',
      'lib/marketplace_merchant_catalogue.dart',
      'lib/marketplace_merchant_settlements.dart',
      'lib/marketplace_checkout_page.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    for (final message in banned) {
      expect(sources, isNot(contains(message)), reason: message);
    }
  });
}

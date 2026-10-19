import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source contract for the driver floating-offer administrative flag.
///
/// A failed `driver_floating_offer_config` call must fail closed, must not be
/// cached as "disabled", and must not be presented as "not enabled in your
/// environment". The channel passed to the RPC must stay the server-resolved
/// `ExpressRuntimeChannel.name`; the client never chooses Preview or Production.
void main() {
  late String home;

  setUpAll(() {
    home = File('lib/video_style_home.dart').readAsStringSync();
  });

  String section(String startMarker, String endMarker) {
    final start = home.indexOf(startMarker);
    expect(start, isNonNegative, reason: 'missing $startMarker');
    final end = home.indexOf(endMarker, start);
    expect(end, greaterThan(start), reason: 'missing $endMarker');
    return home.substring(start, end);
  }

  test('loader tracks unavailable separately from disabled', () {
    final loader = section(
      '  Future<bool> _loadFloatingOfferAdminFlag',
      '  /// Select only authorized requests',
    );

    expect(home, contains('bool _floatingAdminUnavailable = false;'));
    expect(loader, contains('bool unavailable = false;'));
    expect(loader, contains('unavailable = true;'));
    expect(loader, contains('_floatingAdminUnavailable = unavailable;'));
  });

  test('failed lookup is never cached and never reported as enabled', () {
    final loader = section(
      '  Future<bool> _loadFloatingOfferAdminFlag',
      '  /// Select only authorized requests',
    );

    expect(
      loader,
      contains('_floatingAdminCheckedAt = unavailable ? null : DateTime.now().toUtc();'),
    );
    expect(loader, contains('!_floatingAdminUnavailable &&'));
    expect(loader, isNot(contains('catch (_)')));
    expect(loader, contains('enabled = raw == true;'));
    expect(loader, contains("'p_channel': ExpressRuntimeChannel.name"));
  });

  test('settings dialog distinguishes a failed check from a disabled flag', () {
    final start = home.indexOf('  Future<void> _showFloatingOfferSettings()');
    expect(start, isNonNegative);
    // The dialog body is the first ~3500 characters of the method.
    final dialog = home.substring(start, start + 3500);
    final dialogFallback = section(
      '  Future<void> _showFloatingOfferSettings()',
      'SwitchListTile(',
    );

    expect(dialogFallback, contains('final adminUnavailable = _floatingAdminUnavailable;'));
    expect(
      dialogFallback,
      contains("'No pudimos verificar esta función."),
    );
    expect(
      dialogFallback,
      contains("'Esta función no está habilitada en tu entorno.'"),
    );
    // Fail closed: the switch stays locked while the admin flag is not true.
    expect(dialog, contains('onChanged: !adminOn || !permissionGranted'));
    expect(dialog, contains('value: enabled && adminOn && permissionGranted'));
  });
}

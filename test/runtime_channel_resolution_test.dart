import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/core/runtime_channel.dart';

void main() {
  tearDown(ExpressRuntimeChannel.resetForSignedOutUser);

  test('starts in the safe default until the account is resolved', () {
    ExpressRuntimeChannel.resetForSignedOutUser();

    expect(ExpressRuntimeChannel.previewMode, isFalse);
    expect(ExpressRuntimeChannel.name, 'production');
  });

  test('the authenticated account can resolve to Preview', () {
    ExpressRuntimeChannel.applyResolvedEnvironment('preview');

    expect(ExpressRuntimeChannel.previewMode, isTrue);
    expect(ExpressRuntimeChannel.name, 'preview');
  });

  test('the authenticated account can resolve to Production', () {
    ExpressRuntimeChannel.applyResolvedEnvironment('preview');
    ExpressRuntimeChannel.applyResolvedEnvironment('production');

    expect(ExpressRuntimeChannel.previewMode, isFalse);
    expect(ExpressRuntimeChannel.name, 'production');
  });

  test('signing out clears the resolved account environment', () {
    ExpressRuntimeChannel.applyResolvedEnvironment('preview');
    ExpressRuntimeChannel.resetForSignedOutUser();

    expect(ExpressRuntimeChannel.previewMode, isFalse);
    expect(ExpressRuntimeChannel.name, 'production');
  });

  test('invalid server environment is rejected', () {
    expect(
      () => ExpressRuntimeChannel.applyResolvedEnvironment('qa'),
      throwsArgumentError,
    );
  });

  test('Preview debt errors keep the amount but hide SQL codes', () {
    ExpressRuntimeChannel.applyResolvedEnvironment('preview');

    final safe = ExpressRuntimeChannel.userSafeError(
      Exception('Deuda por cancelación de 500 CLP. code: P0001'),
    );

    expect(safe, contains('CLP 500'));
    expect(safe, isNot(contains('P0001')));
  });

  test('Preview technical errors never expose PostgREST diagnostics', () {
    ExpressRuntimeChannel.applyResolvedEnvironment('preview');

    final safe = ExpressRuntimeChannel.userSafeError(
      Exception(
        'PostgrestException(status: 400, details: Bad Request, code: 23505)',
      ),
    );

    expect(safe, 'No pudimos completar esta acción. Intenta nuevamente.');
    expect(safe, isNot(contains('PostgrestException')));
    expect(safe, isNot(contains('23505')));
  });
}

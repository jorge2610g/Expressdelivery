import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/core/runtime_channel.dart';

void main() {
  tearDown(ExpressRuntimeChannel.resetToCompiledMode);

  test('Preview build remains Preview by default', () {
    ExpressRuntimeChannel.configureCompiledMode(true);

    expect(ExpressRuntimeChannel.compiledPreviewMode, isTrue);
    expect(ExpressRuntimeChannel.previewMode, isTrue);
    expect(ExpressRuntimeChannel.name, 'preview');
  });

  test('Production build can adopt server-resolved Preview session', () {
    ExpressRuntimeChannel.configureCompiledMode(false);
    ExpressRuntimeChannel.applyResolvedEnvironment('preview');

    expect(ExpressRuntimeChannel.compiledPreviewMode, isFalse);
    expect(ExpressRuntimeChannel.previewMode, isTrue);
    expect(ExpressRuntimeChannel.name, 'preview');

    ExpressRuntimeChannel.resetToCompiledMode();
    expect(ExpressRuntimeChannel.name, 'production');
  });

  test('Invalid server environment is rejected', () {
    ExpressRuntimeChannel.configureCompiledMode(false);

    expect(
      () => ExpressRuntimeChannel.applyResolvedEnvironment('qa'),
      throwsArgumentError,
    );
  });

  test('Preview debt errors keep the amount but hide SQL codes', () {
    ExpressRuntimeChannel.configureCompiledMode(true);
    ExpressRuntimeChannel.applyResolvedEnvironment('preview');

    final safe = ExpressRuntimeChannel.userSafeError(
      Exception('Deuda por cancelación de 500 CLP. code: P0001'),
    );

    expect(safe, contains('CLP 500'));
    expect(safe, isNot(contains('P0001')));
  });

  test('Preview technical errors never expose PostgREST diagnostics', () {
    ExpressRuntimeChannel.configureCompiledMode(true);
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

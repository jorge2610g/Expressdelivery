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

  test('Production build cannot switch to Preview backend', () {
    ExpressRuntimeChannel.configureCompiledMode(false);

    expect(
      () => ExpressRuntimeChannel.applyResolvedEnvironment('preview'),
      throwsStateError,
    );
    expect(ExpressRuntimeChannel.name, 'production');
  });

  test('Preview build cannot switch to Production backend', () {
    ExpressRuntimeChannel.configureCompiledMode(true);

    expect(
      () => ExpressRuntimeChannel.applyResolvedEnvironment('production'),
      throwsStateError,
    );
    expect(ExpressRuntimeChannel.name, 'preview');
  });

  test('matching server environment remains supported', () {
    ExpressRuntimeChannel.configureCompiledMode(false);
    ExpressRuntimeChannel.applyResolvedEnvironment('production');
    expect(ExpressRuntimeChannel.name, 'production');

    ExpressRuntimeChannel.configureCompiledMode(true);
    ExpressRuntimeChannel.applyResolvedEnvironment('preview');
    expect(ExpressRuntimeChannel.name, 'preview');
  });

  test('Invalid server environment is rejected', () {
    ExpressRuntimeChannel.configureCompiledMode(false);

    expect(
      () => ExpressRuntimeChannel.applyResolvedEnvironment('qa'),
      throwsArgumentError,
    );
  });
}

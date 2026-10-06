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
}

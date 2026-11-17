import 'package:expressdelivery/core/runtime_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ExpressRuntimeChannel.resetForSignedOutUser);

  test('sin entorno resuelto el modo conductor web queda cerrado', () {
    ExpressRuntimeChannel.resetForSignedOutUser();
    expect(ExpressRuntimeChannel.webDriverModeAllowed, isFalse);
  });

  test('cuenta de Prueba habilita el modo conductor en la web', () {
    ExpressRuntimeChannel.applyResolvedEnvironment('preview');
    expect(ExpressRuntimeChannel.webDriverModeAllowed, isTrue);
  });

  test('cuenta de Producción no habilita el modo conductor en la web', () {
    ExpressRuntimeChannel.applyResolvedEnvironment('production');
    expect(ExpressRuntimeChannel.webDriverModeAllowed, isFalse);
  });
}

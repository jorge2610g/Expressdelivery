import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/video_style_home.dart';

void main() {
  test('network drops never expose raw exceptions or URLs', () {
    const raw =
        'ClientException: Software caused connection abort, '
        'uri=https://zgpijrznvaskgcmauwxx.supabase.co/rest/v1/rpc/'
        'my_current_country_trips_v2';
    final text = expressFriendlyLoadError(Exception(raw));
    expect(text, contains('Reintentando'));
    expect(text.contains('supabase'), isFalse);
    expect(text.contains('ClientException'), isFalse);
  });

  test('timeouts and socket errors are treated as network', () {
    for (final raw in [
      'SocketException: Failed host lookup',
      'TimeoutException after 0:00:10',
      'Connection reset by peer',
    ]) {
      expect(expressFriendlyLoadError(raw), contains('Reintentando'));
    }
  });

  test('other errors get a generic message without internals', () {
    final text = expressFriendlyLoadError(
      Exception('PostgrestException(message: boom, code: 500)'),
    );
    expect(text, 'No se pudo cargar el modo conductor. Intenta nuevamente.');
  });

  test('null error falls back to generic message', () {
    expect(
      expressFriendlyLoadError(null),
      'No se pudo cargar el modo conductor. Intenta nuevamente.',
    );
  });
}

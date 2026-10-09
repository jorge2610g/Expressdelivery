import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/core/supabase_client.dart';

void main() {
  test('Express compile-time channel selects only its own Supabase project', () {
    const preview = bool.fromEnvironment(
      'EXPRESS_PREVIEW_MODE',
      defaultValue: false,
    );

    expect(expressPreviewSupabase, preview);
    expect(
      supabaseUrl,
      preview
          ? 'https://xbphilqezmwfjfpdbwad.supabase.co'
          : 'https://zgpijrznvaskgcmauwxx.supabase.co',
    );
    expect(supabasePublishableKey, startsWith('sb_publishable_'));
  });
}

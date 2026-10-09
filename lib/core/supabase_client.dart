import 'package:supabase_flutter/supabase_flutter.dart';

// The app has ONE functional implementation and two independent Supabase
// projects. The build flag is the only selector for the data plane.
// Keep Production's default unchanged for existing signed/store builds.
const bool expressPreviewSupabase = bool.fromEnvironment(
  'EXPRESS_PREVIEW_MODE',
  defaultValue: false,
);

const supabaseUrl = expressPreviewSupabase
    ? 'https://xbphilqezmwfjfpdbwad.supabase.co'
    : 'https://zgpijrznvaskgcmauwxx.supabase.co';

// Publishable keys are public client identifiers, never service-role secrets.
// Different keys ensure that a Preview JWT cannot be used against Production.
const supabasePublishableKey = expressPreviewSupabase
    ? 'sb_publishable_Gj9wcPPgkBhypbL8xIx2-w_guLesRNY'
    : 'sb_publishable_MALGs-X8KdmJSq-QQzeazQ_p5xsfrZP';

SupabaseClient get supabase => Supabase.instance.client;

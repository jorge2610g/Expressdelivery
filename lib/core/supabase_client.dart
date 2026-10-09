import 'package:supabase_flutter/supabase_flutter.dart';

// Both APKs share this exact code. The compiled mode selects only credentials;
// no Preview binary is allowed to fall back to the Production database.
const bool expressBuildIsPreview = bool.fromEnvironment(
  'EXPRESS_PREVIEW_MODE',
  defaultValue: false,
);

const String _productionSupabaseUrl =
    'https://zgpijrznvaskgcmauwxx.supabase.co';
const String _productionPublishableKey =
    'sb_publishable_MALGs-X8KdmJSq-QQzeazQ_p5xsfrZP';

const String _previewSupabaseUrl = String.fromEnvironment(
  'EXPRESS_PREVIEW_SUPABASE_URL',
);
const String _previewPublishableKey = String.fromEnvironment(
  'EXPRESS_PREVIEW_SUPABASE_PUBLISHABLE_KEY',
);

const String supabaseUrl =
    expressBuildIsPreview ? _previewSupabaseUrl : _productionSupabaseUrl;
const String supabasePublishableKey =
    expressBuildIsPreview ? _previewPublishableKey : _productionPublishableKey;

/// Runs before Supabase.initialize and before any auth/session can be restored.
/// Bad or absent Preview build config causes a startup error, not a connection to
/// live users. Do not let the resolved per-user runtime channel override this.
void validateExpressSupabaseEnvironment({required bool previewMode}) {
  if (previewMode != expressBuildIsPreview) {
    throw StateError('El entorno de ejecución no coincide con el APK firmado.');
  }

  final uri = Uri.tryParse(supabaseUrl);
  final expectedHost = previewMode
      ? 'xbphilqezmwfjfpdbwad.supabase.co'
      : 'zgpijrznvaskgcmauwxx.supabase.co';

  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != expectedHost ||
      uri.hasPort ||
      uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw StateError(
      previewMode
          ? 'Express Preview bloqueado: Supabase Preview no está configurado.'
          : 'Express Producción bloqueado: proyecto Supabase incorrecto.',
    );
  }

  if (!supabasePublishableKey.startsWith('sb_publishable_') ||
      supabasePublishableKey.length < 24 ||
      (previewMode && supabasePublishableKey == _productionPublishableKey)) {
    throw StateError(
      'Express no iniciará: falta la clave pública del Supabase correcto.',
    );
  }
}

SupabaseClient get supabase => Supabase.instance.client;

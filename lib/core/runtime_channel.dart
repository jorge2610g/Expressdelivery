class ExpressRuntimeChannel {
  ExpressRuntimeChannel._();

  static bool compiledPreviewMode = false;
  static bool previewMode = false;

  static void configureCompiledMode(bool value) {
    compiledPreviewMode = value;
    previewMode = value;
  }

  static void applyResolvedEnvironment(String environment) {
    final normalized = environment.trim().toLowerCase();
    if (normalized != 'preview' && normalized != 'production') {
      throw ArgumentError.value(
        environment,
        'environment',
        'Express runtime environment must be preview or production',
      );
    }
    // Two independent Supabase projects: a session cannot switch data planes.
    // Production-binary internal QA must use explicit Preview backend builds.
    if ((normalized == 'preview') != compiledPreviewMode) {
      throw StateError(
        'Cross-project runtime switching is forbidden; use the matching Express build.',
      );
    }
    previewMode = compiledPreviewMode;
  }

  static void resetToCompiledMode() {
    previewMode = compiledPreviewMode;
  }

  static String get name => previewMode ? 'preview' : 'production';

  static String userSafeError(
    Object? error, {
    String fallback = 'No pudimos completar esta acción. Intenta nuevamente.',
  }) {
    if (!previewMode || error == null) return fallback;
    final detail = error.toString().trim();
    return detail.isEmpty ? fallback : '$fallback\n\n$detail';
  }

  static String technicalOr({
    required String production,
    required String preview,
  }) =>
      previewMode ? preview : production;
}

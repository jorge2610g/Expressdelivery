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
    previewMode = normalized == 'preview';
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

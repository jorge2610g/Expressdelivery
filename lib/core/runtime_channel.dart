class ExpressRuntimeChannel {
  ExpressRuntimeChannel._();

  static bool previewMode = false;

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

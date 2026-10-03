class ExpressRuntimeChannel {
  ExpressRuntimeChannel._();

  static bool previewMode = false;

  static String get name => previewMode ? 'preview' : 'production';
}

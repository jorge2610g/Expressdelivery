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
    if (detail.isEmpty) return fallback;

    final normalized = detail.toLowerCase();
    if (normalized.contains('deuda') &&
        (normalized.contains('cancelación') ||
            normalized.contains('cancelacion'))) {
      final amount = RegExp(
        r'\b(?:(CLP|BOB)\s*([0-9][0-9.,]*)|([0-9][0-9.,]*)\s*(CLP|BOB))',
        caseSensitive: false,
      ).firstMatch(detail);
      if (amount != null) {
        final currency = (amount.group(1) ?? amount.group(4))!.toUpperCase();
        final value = (amount.group(2) ?? amount.group(3))!.replaceFirst(
          RegExp(r'[.,]+$'),
          '',
        );
        return 'Tienes una deuda pendiente por cancelación de $currency '
            '$value. Revísala en Pagos y billetera.';
      }
      return 'Tienes una deuda pendiente por cancelación. Revísala en Pagos y '
          'billetera.';
    }

    // Preview permite detalles funcionales para depuración, pero nunca debe
    // filtrar códigos SQL, respuestas HTTP ni excepciones crudas en pantalla.
    final containsInternalDetails = RegExp(
      r'PostgrestException|FunctionsHttpException|\bcode\s*:|\bdetails\s*:|'
      r'\bhint\s*:|\bP\d{4}\b|Bad Request|status\s*:\s*\d{3}',
      caseSensitive: false,
    ).hasMatch(detail);
    return containsInternalDetails ? fallback : '$fallback\n\n$detail';
  }

  static String technicalOr({
    required String production,
    required String preview,
  }) => previewMode ? preview : production;
}

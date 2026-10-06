import 'mobile_main.dart' as express;

/// Compatibility entry point for local tools.
///
/// CI, Shorebird and QA now compile lib/mobile_main.dart for both Preview and
/// Production. This wrapper intentionally contains no startup logic of its own.
void main() {
  express.runExpressMobile(
    previewMode: true,
    packageName: 'com.express.usuario.preview',
  );
}

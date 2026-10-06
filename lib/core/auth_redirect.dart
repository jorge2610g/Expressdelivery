const String expressCompiledPackageName = String.fromEnvironment(
  'EXPRESS_FIREBASE_PACKAGE_NAME',
  defaultValue: 'com.express.usuario1',
);

const String expressWebAuthRedirectUrl =
    'https://jorge2610g.github.io/Expressdelivery/';

String expressAuthRedirectUrl({
  required bool isWeb,
  String packageName = expressCompiledPackageName,
}) {
  if (isWeb) return expressWebAuthRedirectUrl;

  final normalized = packageName.trim();
  if (normalized.isEmpty) {
    throw StateError('EXPRESS_FIREBASE_PACKAGE_NAME is empty');
  }

  return '$normalized://login-callback/';
}

import 'dart:html' as html;
import 'dart:js' as js;

void reloadExpressApp(String targetVersion) {
  try {
    final forceUpdate = js.context['expressForceAppUpdate'];
    if (forceUpdate != null) {
      js.context.callMethod(
        'expressForceAppUpdate',
        <Object?>[targetVersion],
      );
      return;
    }
  } catch (_) {}

  final current = Uri.base;
  final query = Map<String, String>.from(current.queryParameters)
    ..['express_update'] = targetVersion
    ..['_t'] = DateTime.now().millisecondsSinceEpoch.toString();

  final next = current.replace(queryParameters: query).toString();
  html.window.location.replace(next);
}

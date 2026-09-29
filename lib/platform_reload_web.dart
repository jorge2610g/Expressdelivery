import 'dart:html' as html;

void reloadExpressApp(String targetVersion) {
  final current = Uri.base;
  final query = Map<String, String>.from(current.queryParameters)
    ..['express_update'] = targetVersion
    ..['_t'] = DateTime.now().millisecondsSinceEpoch.toString();

  final next = current.replace(queryParameters: query).toString();
  html.window.location.replace(next);
}

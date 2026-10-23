// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

const _intentKey = 'express.driverRegistrationIntent';

bool get hasPendingDriverRegistrationIntent {
  try {
    final startedAt = int.tryParse(
      html.window.sessionStorage[_intentKey] ?? '',
    );
    if (startedAt == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - startedAt;
    if (age < 0 || age > const Duration(minutes: 10).inMilliseconds) {
      clearDriverRegistrationIntent();
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

void rememberDriverRegistrationIntent() {
  try {
    html.window.sessionStorage[_intentKey] = DateTime.now()
        .millisecondsSinceEpoch
        .toString();
  } catch (_) {
    // The URL remains the primary route signal if browser storage is blocked.
  }
}

void completeDriverRegistrationIntent() {
  try {
    final current = Uri.parse(html.window.location.href);
    final hasRegistrationQuery =
        current.queryParameters['registro']?.toLowerCase() == 'conductor';
    final hasRegistrationPath =
        current.pathSegments
            .where((segment) => segment.isNotEmpty)
            .map((segment) => segment.toLowerCase())
            .toList()
            .join('/') ==
        'registro/conductor';
    if (!hasRegistrationQuery && !hasRegistrationPath) {
      html.window.history.replaceState(
        null,
        '',
        current
            .replace(
              path: '/',
              queryParameters: {
                ...current.queryParameters,
                'registro': 'conductor',
              },
            )
            .toString(),
      );
    }
    clearDriverRegistrationIntent();
  } catch (_) {
    // Continue to show the captured registration flow even if URL updates fail.
  }
}

void clearDriverRegistrationIntent() {
  try {
    html.window.sessionStorage.remove(_intentKey);
  } catch (_) {}
}

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

const _key = 'express.restaurantLoginIntent';

void rememberRestaurantLoginIntent() {
  try {
    html.window.sessionStorage[_key] =
        DateTime.now().millisecondsSinceEpoch.toString();
  } catch (_) {}
}

bool consumeRestaurantLoginIntent() {
  try {
    final startedAt = int.tryParse(html.window.sessionStorage[_key] ?? '');
    html.window.sessionStorage.remove(_key);
    if (startedAt == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - startedAt;
    return age >= 0 && age <= const Duration(minutes: 15).inMilliseconds;
  } catch (_) {
    return false;
  }
}

void goToRestaurantPortal() {
  try {
    html.window.location.replace('/restaurantes/');
  } catch (_) {}
}

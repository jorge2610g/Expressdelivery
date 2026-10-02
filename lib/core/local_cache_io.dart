import 'dart:io';

String _safeKey(String key) =>
    key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

Future<File> _cacheFile(String key) async {
  final dir = Directory(
    '${Directory.systemTemp.path}/expressdelivery_runtime_cache',
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return File('${dir.path}/${_safeKey(key)}.json');
}

Future<String?> readCacheText(String key) async {
  try {
    final file = await _cacheFile(key);
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> writeCacheText(String key, String value) async {
  try {
    final file = await _cacheFile(key);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  } catch (_) {
    // El caché nunca debe bloquear la aplicación.
  }
}

Future<void> deleteCacheText(String key) async {
  try {
    final file = await _cacheFile(key);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Ignorar fallos de caché.
  }
}

import 'dart:async';
import 'dart:convert';

import 'local_cache_stub.dart'
    if (dart.library.io) 'local_cache_io.dart' as platform;

class CachedJsonValue {
  final Object? value;
  final DateTime savedAt;

  const CachedJsonValue({
    required this.value,
    required this.savedAt,
  });

  Duration age(DateTime now) => now.difference(savedAt);
}

class LocalJsonCache {
  LocalJsonCache._();

  static final Map<String, CachedJsonValue> _memory = <String, CachedJsonValue>{};

  static Future<CachedJsonValue?> read(String key) async {
    final memory = _memory[key];
    if (memory != null) return memory;

    final raw = await platform.readCacheText(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final savedAtRaw = decoded['saved_at']?.toString();
      if (savedAtRaw == null) return null;
      final savedAt = DateTime.tryParse(savedAtRaw)?.toUtc();
      if (savedAt == null) return null;
      final value = decoded['value'];
      final cached = CachedJsonValue(value: value, savedAt: savedAt);
      _memory[key] = cached;
      return cached;
    } catch (_) {
      await platform.deleteCacheText(key);
      return null;
    }
  }

  static Future<void> write(String key, Object? value) async {
    final savedAt = DateTime.now().toUtc();
    _memory[key] = CachedJsonValue(value: value, savedAt: savedAt);

    final payload = jsonEncode(<String, Object?>{
      'saved_at': savedAt.toIso8601String(),
      'value': value,
    });
    await platform.writeCacheText(key, payload);
  }

  static Future<void> remove(String key) async {
    _memory.remove(key);
    await platform.deleteCacheText(key);
  }

  static Future<void> clearMemory() async {
    _memory.clear();
  }
}

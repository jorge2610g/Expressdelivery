import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

String expressSupabaseSessionKey() =>
    'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

/// Supabase auth storage that never lets a malformed/legacy preference prevent
/// Express from starting. The Android package still owns its own preferences,
/// so Preview and Production remain isolated even though the logical key is the
/// same for the shared Supabase project.
class ResilientExpressLocalStorage extends LocalStorage {
  ResilientExpressLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  SharedPreferences? _preferences;
  String? _memorySession;
  Future<void>? _initialization;

  @override
  Future<void> initialize() {
    return _initialization ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    try {
      _preferences = await SharedPreferences.getInstance();
    } catch (_) {
      // Keep auth usable in memory. Storage trouble must never brick startup.
      _preferences = null;
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    await initialize();
    try {
      if (_preferences?.containsKey(persistSessionKey) == true) {
        return true;
      }
    } catch (_) {
      // Fall through to the in-memory copy.
    }
    return _memorySession != null;
  }

  @override
  Future<String?> accessToken() async {
    await initialize();

    try {
      final value = _preferences?.getString(persistSessionKey);
      if (value != null && value.isNotEmpty) {
        _memorySession = value;
        return value;
      }
    } catch (_) {
      // A previous version can leave the same key with an incompatible value.
      // Remove only Express' Supabase auth entry and continue signed out.
      try {
        await _preferences?.remove(persistSessionKey);
      } catch (_) {}
    }

    return _memorySession;
  }

  @override
  Future<void> removePersistedSession() async {
    _memorySession = null;
    await initialize();
    try {
      await _preferences?.remove(persistSessionKey);
    } catch (_) {}
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    _memorySession = persistSessionString;
    await initialize();
    try {
      await _preferences?.setString(
        persistSessionKey,
        persistSessionString,
      );
    } catch (_) {
      // The current process keeps the session in memory even if persistence
      // is temporarily unavailable.
    }
  }
}

/// PKCE storage uses the same defensive behavior. A corrupt verifier should
/// invalidate only the pending OAuth attempt, never the whole application.
class ResilientExpressPkceStorage extends GotrueAsyncStorage {
  SharedPreferences? _preferences;
  Future<SharedPreferences?>? _initialization;

  Future<SharedPreferences?> _prefs() {
    return _initialization ??= _loadPreferences();
  }

  Future<SharedPreferences?> _loadPreferences() async {
    try {
      return _preferences = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getItem({required String key}) async {
    try {
      return (await _prefs())?.getString(key);
    } catch (_) {
      try {
        await (await _prefs())?.remove(key);
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> removeItem({required String key}) async {
    try {
      await (await _prefs())?.remove(key);
    } catch (_) {}
  }

  @override
  Future<void> setItem({
    required String key,
    required String value,
  }) async {
    try {
      await (await _prefs())?.setString(key, value);
    } catch (_) {}
  }
}

Future<void> initializeExpressSupabase() {
  return Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: ResilientExpressLocalStorage(
        persistSessionKey: expressSupabaseSessionKey(),
      ),
      pkceAsyncStorage: ResilientExpressPkceStorage(),
    ),
  );
}

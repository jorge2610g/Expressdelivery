import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expressdelivery/core/express_supabase_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'sb-zgpijrznvaskgcmauwxx-auth-token';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('derives the expected Supabase session key', () {
    expect(expressSupabaseSessionKey(), key);
  });

  test('reads and removes a healthy persisted session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      key: '{"access_token":"token"}',
    });

    final storage = ResilientExpressLocalStorage(
      persistSessionKey: key,
    );

    await storage.initialize();
    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), '{"access_token":"token"}');

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
  });

  test('wrong SharedPreferences type cannot brick startup', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      key: true,
    });

    final storage = ResilientExpressLocalStorage(
      persistSessionKey: key,
    );

    await storage.initialize();
    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(key), isFalse);
  });

  test('session writes remain usable after initialization', () async {
    final storage = ResilientExpressLocalStorage(
      persistSessionKey: key,
    );

    await storage.initialize();
    await storage.persistSession('session-value');

    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), 'session-value');
  });

  test('wrong PKCE preference type is discarded safely', () async {
    const verifierKey = 'qa-code-verifier';
    SharedPreferences.setMockInitialValues(<String, Object>{
      verifierKey: 123,
    });

    final storage = ResilientExpressPkceStorage();
    expect(await storage.getItem(key: verifierKey), isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(verifierKey), isFalse);
  });
}

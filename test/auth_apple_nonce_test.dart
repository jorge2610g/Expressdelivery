import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/auth_apple_nonce.dart';

void main() {
  test('el nonce crudo tiene 32 caracteres del conjunto permitido', () {
    final nonce = expressAppleRawNonce();
    expect(nonce.length, 32);
    expect(
      RegExp(r'^[0-9A-Za-z\-._]+$').hasMatch(nonce),
      isTrue,
      reason: 'solo caracteres seguros para Supabase y Apple',
    );
  });

  test('dos nonces seguidos no coinciden', () {
    expect(expressAppleRawNonce(), isNot(expressAppleRawNonce()));
  });

  test('el hash del nonce es SHA-256 en hexadecimal (vector conocido)', () {
    // sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    expect(
      expressAppleNonceHash('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}

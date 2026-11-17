import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const _nonceCharset =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

/// Nonce aleatorio que se envía a Supabase tal cual (`nonce`).
/// Apple recibe solo su hash SHA-256 y lo devuelve dentro del identity token.
String expressAppleRawNonce([int length = 32]) {
  final random = Random.secure();
  return List.generate(
    length,
    (_) => _nonceCharset[random.nextInt(_nonceCharset.length)],
  ).join();
}

/// Hash SHA-256 en hexadecimal del nonce crudo, para la solicitud a Apple.
String expressAppleNonceHash(String rawNonce) {
  return sha256.convert(utf8.encode(rawNonce)).toString();
}

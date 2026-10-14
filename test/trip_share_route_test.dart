import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/web_main.dart';

void main() {
  group('expressTripShareTokenFromUri', () {
    test('accepts a 64-character hex token', () {
      const token =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final uri = Uri.parse('https://expressviajes.online/?trip_share=$token');

      expect(expressTripShareTokenFromUri(uri), token);
    });

    test('normalizes uppercase tokens', () {
      const token =
          'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789';
      final uri = Uri.parse('https://expressviajes.online/?trip_share=$token');

      expect(
        expressTripShareTokenFromUri(uri),
        token.toLowerCase(),
      );
    });

    test('rejects missing or malformed tokens', () {
      expect(
        expressTripShareTokenFromUri(
          Uri.parse('https://expressviajes.online/'),
        ),
        isNull,
      );
      expect(
        expressTripShareTokenFromUri(
          Uri.parse('https://expressviajes.online/?trip_share=abc'),
        ),
        isNull,
      );
      expect(
        expressTripShareTokenFromUri(
          Uri.parse(
            'https://expressviajes.online/?trip_share=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
          ),
        ),
        isNull,
      );
    });
  });
}

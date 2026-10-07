import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/push_deduplication.dart';

void main() {
  test('prefers backend notification id for persistent deduplication', () {
    expect(
      expressPushStableKey(
        channel: 'preview',
        notificationId: 'notification-123',
        messageId: 'firebase-456',
      ),
      'preview:notification-123',
    );
  });

  test('falls back to Firebase message id when notification id is absent', () {
    expect(
      expressPushStableKey(
        channel: 'production',
        messageId: 'firebase-456',
      ),
      'production:firebase-456',
    );
  });

  test('keeps Preview and Production dedupe scopes isolated', () {
    expect(
      expressPushStableKey(channel: 'preview', notificationId: 'same'),
      isNot(
        expressPushStableKey(channel: 'production', notificationId: 'same'),
      ),
    );
  });

  test('stable Android notification id is deterministic and positive', () {
    final first = expressPushStableNotificationId('preview:notification-123');
    final second = expressPushStableNotificationId('preview:notification-123');

    expect(first, second);
    expect(first, greaterThan(0));
  });
}

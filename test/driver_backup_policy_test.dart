import 'package:expressdelivery/driver_backup_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 15, 12);

  test('sin suscripción de Realtime el respaldo consulta siempre (ritmo original)', () {
    expect(driverBackupFallbackInterval, const Duration(seconds: 12));
    expect(
      driverBackupDue(channelSubscribed: false, lastActivityAt: now, now: now),
      isTrue,
    );
  });

  test('con Realtime suscrito y pantalla recién actualizada, no consulta', () {
    expect(
      driverBackupDue(
        channelSubscribed: true,
        lastActivityAt: now.subtract(const Duration(seconds: 12)),
        now: now,
      ),
      isFalse,
    );
  });

  test('con Realtime suscrito y 30 s sin actividad, sí consulta', () {
    expect(driverBackupHealthyInterval, const Duration(seconds: 30));
    expect(
      driverBackupDue(
        channelSubscribed: true,
        lastActivityAt: now.subtract(const Duration(seconds: 30)),
        now: now,
      ),
      isTrue,
    );
  });

  test('sin ninguna actividad previa, consulta', () {
    expect(
      driverBackupDue(channelSubscribed: true, lastActivityAt: null, now: now),
      isTrue,
    );
  });
}

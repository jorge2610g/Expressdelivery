import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  _tripPaymentRequestContract();
  late String migration;

  setUpAll(() {
    final file = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('_driver_payment_qr.sql'));
    migration = file.readAsStringSync();
  });

  test('el bucket del QR es privado y sin lectura pública', () {
    expect(migration, contains("'driver-payment-qr'"));
    expect(migration, contains('false,'));
    expect(migration, isNot(contains('public = true')));
  });

  test('el pasajero solo lee en el paso de cobro, del mismo entorno', () {
    expect(migration, contains("t.status = 'completed'"));
    expect(migration, contains("t.payment_status = 'pending'"));
    expect(migration, contains('t.channel = coalesce('));
    expect(migration, contains("'production')"));
  });

  test('la lectura de pasajero no sale de la carpeta del conductor', () {
    expect(migration, contains("split_part(p_path, '/', 1)"));
  });

  test('la RPC del conductor valida dueño y formato de la ruta', () {
    expect(migration, contains('set_my_payment_qr_path'));
    expect(migration, contains("split_part(p_path, '/', 1) <> v_uid::text"));
    expect(migration, contains(r"'^[0-9a-f-]{36}/qr/[0-9]+\.(png|jpe?g|webp)$'"));
  });

  test('no toca montos, tarifas ni cobros', () {
    final lower = migration.toLowerCase();
    expect(lower, isNot(contains('final_fare')));
    expect(lower, isNot(contains('passenger_due_amount')));
    expect(lower, isNot(contains('insert into public.payment_transactions')));
    expect(lower, isNot(contains('wallet')));
  });
}

void _tripPaymentRequestContract() {
  late String migration;

  setUpAll(() {
    final file = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('_trip_payment_request.sql'));
    migration = file.readAsStringSync();
  });

  test('Cobrar solo registra el momento del cobro', () {
    expect(migration, contains('add column if not exists payment_requested_at'));
    expect(
      migration,
      contains(
        'set payment_requested_at = coalesce(t.payment_requested_at, now())',
      ),
    );
  });

  test('Cobrar solo lo puede pedir el conductor del viaje en curso', () {
    expect(migration, contains('and t.driver_id = v_uid'));
    expect(migration, contains("and t.status = 'in_progress'"));
  });

  test('el QR se lee en curso con cobro pedido o completado con cobro pendiente',
      () {
    expect(migration, contains('payment_requested_at is not null'));
    expect(migration, contains("t.payment_status = 'pending'"));
  });

  test('no cambia montos, tarifas ni billetera', () {
    final lower = migration.toLowerCase();
    expect(lower, isNot(contains('final_fare =')));
    expect(lower, isNot(contains('passenger_due_amount =')));
    expect(lower, isNot(contains('wallet')));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/avisos_page.dart';

void main() {
  test('categorías conocidas y valor por defecto', () {
    expect(AvisoCategory.of('evento').label, 'Evento');
    expect(AvisoCategory.of('importante').label, 'Importante');
    expect(AvisoCategory.of('otra').label, 'Aviso');
    expect(AvisoCategory.of(null).label, 'Aviso');
  });

  test('nota de caducidad solo si el aviso caduca', () {
    expect(avisoExpiryNote(null), '');
    expect(
      avisoExpiryNote('2026-12-24T18:00:00+00:00'),
      contains('se elimina automáticamente'),
    );
  });
}

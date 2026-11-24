import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/avisos_page.dart';

void main() {
  botonesTest();
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

void botonesTest() {
  test('solo se muestran botones con texto y enlace https, máximo 3', () {
    final out = avisoButtons([
      {'label': 'Mapa', 'url': 'https://a.com'},
      {'label': 'Malo', 'url': 'http://a.com'},
      {'label': '', 'url': 'https://b.com'},
      {'label': 'B', 'url': 'https://b.com'},
      {'label': 'C', 'url': 'https://c.com'},
      {'label': 'D', 'url': 'https://d.com'},
    ]);
    expect(out.length, 3);
    expect(out.first['label'], 'Mapa');
    expect(avisoButtons(null), isEmpty);
  });
}

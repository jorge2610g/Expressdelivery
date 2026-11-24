import 'package:expressdelivery/business_hours.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('horario vacío no muestra nada', () {
    expect(formatBusinessHours(<String, dynamic>{}), '');
    expect(formatBusinessHours(null), '');
    expect(businessHoursEmpty({'mon': []}), isTrue);
  });

  test('agrupa días consecutivos con el mismo horario', () {
    final text = formatBusinessHours({
      'mon': [{'from': '09:00', 'to': '22:00'}],
      'tue': [{'from': '09:00', 'to': '22:00'}],
      'wed': [{'from': '09:00', 'to': '22:00'}],
      'thu': [{'from': '09:00', 'to': '22:00'}],
      'fri': [{'from': '09:00', 'to': '22:00'}],
      'sat': [{'from': '10:00', 'to': '14:00'}],
      'sun': [],
    });
    expect(text, 'Lun–Vie 09:00–22:00 · Sáb 10:00–14:00');
  });

  test('varios tramos en un día y ida y vuelta al JSON', () {
    final raw = {
      'mon': [
        {'from': '09:00', 'to': '13:00'},
        {'from': '18:00', 'to': '22:00'},
      ],
    };
    expect(formatBusinessHours(raw), 'Lun 09:00–13:00, 18:00–22:00');
    final json = businessHoursToJson(parseBusinessHours(raw));
    expect(json.keys, businessHourDayKeys);
    expect((json['mon'] as List).length, 2);
    expect(json['tue'], isEmpty);
  });
}

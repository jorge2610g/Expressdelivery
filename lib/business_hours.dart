/// Horario semanal de un restaurante: {"mon":[{"from":"09:00","to":"22:00"}], ...}.
/// Un día sin tramos está cerrado.
const List<String> businessHourDayKeys = [
  'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun',
];
const Map<String, String> businessHourDayNames = {
  'mon': 'Lunes',
  'tue': 'Martes',
  'wed': 'Miércoles',
  'thu': 'Jueves',
  'fri': 'Viernes',
  'sat': 'Sábado',
  'sun': 'Domingo',
};
const Map<String, String> _short = {
  'mon': 'Lun',
  'tue': 'Mar',
  'wed': 'Mié',
  'thu': 'Jue',
  'fri': 'Vie',
  'sat': 'Sáb',
  'sun': 'Dom',
};

/// Tramos de cada día; siempre devuelve los siete días.
Map<String, List<({String from, String to})>> parseBusinessHours(Object? raw) {
  final out = <String, List<({String from, String to})>>{};
  final map = raw is Map ? raw : const {};
  for (final day in businessHourDayKeys) {
    final list = map[day];
    out[day] = [
      if (list is List)
        for (final r in list)
          if (r is Map && r['from'] != null && r['to'] != null)
            (from: r['from'].toString(), to: r['to'].toString()),
    ];
  }
  return out;
}

Map<String, dynamic> businessHoursToJson(
    Map<String, List<({String from, String to})>> hours) {
  return {
    for (final day in businessHourDayKeys)
      day: [
        for (final r in hours[day] ?? const <({String from, String to})>[])
          {'from': r.from, 'to': r.to},
      ],
  };
}

bool businessHoursEmpty(Object? raw) =>
    parseBusinessHours(raw).values.every((v) => v.isEmpty);

/// Texto corto para el cliente: «Lun–Vie 09:00–22:00 · Sáb 10:00–14:00».
/// Vacío si el restaurante no configuró horarios.
String formatBusinessHours(Object? raw) {
  final hours = parseBusinessHours(raw);
  if (hours.values.every((v) => v.isEmpty)) return '';
  String ranges(List<({String from, String to})> l) =>
      l.map((r) => '${r.from}–${r.to}').join(', ');
  final parts = <String>[];
  var i = 0;
  while (i < businessHourDayKeys.length) {
    final key = businessHourDayKeys[i];
    final text = ranges(hours[key]!);
    var j = i;
    while (j + 1 < businessHourDayKeys.length &&
        ranges(hours[businessHourDayKeys[j + 1]]!) == text) {
      j++;
    }
    if (text.isNotEmpty) {
      final label = i == j
          ? _short[key]!
          : '${_short[key]}–${_short[businessHourDayKeys[j]]}';
      parts.add('$label $text');
    }
    i = j + 1;
  }
  return parts.join(' · ');
}

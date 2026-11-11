/// Revisa el correo antes de registrar una cuenta o pedir recuperación.
///
/// Los correos mal escritos (por ejemplo «gmial.com» o «gmail.con») rebotan,
/// y muchos rebotes hacen que Supabase restrinja el envío de correos del
/// proyecto. Esta revisión detecta el formato inválido y sugiere el dominio
/// correcto para los proveedores más usados.
class EmailTypoGuard {
  EmailTypoGuard._();

  static const List<String> knownDomains = [
    'gmail.com',
    'hotmail.com',
    'hotmail.es',
    'outlook.com',
    'outlook.es',
    'live.com',
    'yahoo.com',
    'yahoo.es',
    'icloud.com',
  ];

  static final RegExp _format = RegExp(
    r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,}$",
  );

  /// Quita espacios y pasa a minúsculas.
  static String normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();

  static bool isValidFormat(String value) {
    final email = normalize(value);
    if (email.contains('..')) return false;
    return _format.hasMatch(email);
  }

  /// Devuelve el correo corregido si el dominio parece un error de tipeo de
  /// un proveedor conocido; si no, devuelve `null`.
  static String? suggestion(String value) {
    final email = normalize(value);
    final at = email.lastIndexOf('@');
    if (at <= 0 || at == email.length - 1) return null;
    final local = email.substring(0, at);
    final domain = email.substring(at + 1);
    if (knownDomains.contains(domain)) return null;

    String? best;
    var bestDistance = 3;
    for (final candidate in knownDomains) {
      final d = _distance(domain, candidate);
      if (d < bestDistance) {
        bestDistance = d;
        best = candidate;
      }
    }
    if (best == null || bestDistance == 0) return null;
    return '$local@$best';
  }

  /// Distancia de edición con transposición de letras vecinas.
  static int _distance(String a, String b) {
    final rows = a.length + 1;
    final cols = b.length + 1;
    final d = List.generate(rows, (_) => List<int>.filled(cols, 0));
    for (var i = 0; i < rows; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j < cols; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i < rows; i++) {
      for (var j = 1; j < cols; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = [
          d[i - 1][j] + 1,
          d[i][j - 1] + 1,
          d[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        if (i > 1 &&
            j > 1 &&
            a[i - 1] == b[j - 2] &&
            a[i - 2] == b[j - 1]) {
          final t = d[i - 2][j - 2] + 1;
          if (t < v) v = t;
        }
        d[i][j] = v;
      }
    }
    return d[a.length][b.length];
  }
}

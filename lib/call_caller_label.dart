/// Nombre que se muestra al destinatario de una llamada de voz.
///
/// El SDK de ZEGO reemplaza el marcador `%0` por este nombre. Si el valor llega
/// vacío, con marcadores de plantilla o con caracteres que no son de un nombre,
/// se usa un respaldo amigable en lugar de mostrar texto roto en la pantalla de
/// llamada. El respaldo no revela el rol del llamante, porque el servidor no lo envía.
const String kCallerFallbackLabel = 'Un contacto de Express';

String callerDisplayName(
  String? raw, {
  String fallback = kCallerFallbackLabel,
}) {
  final name = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty || name.length > 60) return fallback;
  if (name.contains('%')) return fallback;
  // Solo letras (incluidas tildes y ñ), espacios, puntos, guiones y apóstrofes.
  final validName = RegExp(r"^\p{L}[\p{L}\p{M} .'\-]*$", unicode: true);
  if (!validName.hasMatch(name)) return fallback;
  return name;
}

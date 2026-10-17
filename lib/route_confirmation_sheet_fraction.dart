/// Altura de la hoja «Confirma tu ruta» como fracción de la pantalla.
///
/// Base: el contenido sin calificación pendiente. Cuando hay una tarjeta de
/// calificación encima, la hoja crece para que la tarjeta y el resto del
/// contenido queden completos y nada se recorte por arriba.
double routeConfirmationSheetFraction({
  required double height,
  required double classicNavigationInset,
  required bool hasPendingRating,
}) {
  if (height <= 0) return .42;

  const baseHeight = 350.0;
  // Tarjeta de calificación (~60 px) más su separación inferior.
  const ratingCardHeight = 76.0;

  final desiredHeight = baseHeight +
      (hasPendingRating ? ratingCardHeight : 0.0) +
      classicNavigationInset;
  final maxFraction = hasPendingRating ? .60 : .50;
  return (desiredHeight / height).clamp(.34, maxFraction).toDouble();
}

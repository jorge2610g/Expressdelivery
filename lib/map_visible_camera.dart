import 'dart:ui' show Offset;

/// Desplazamiento en píxeles para que un punto quede centrado en el área del mapa
/// que realmente se ve: entre el borde superior útil (barra de estado y cabecera)
/// y la parte alta del panel inferior.
///
/// `flutter_map` coloca el punto pedido en el centro del mapa más `offset`, así
/// que el desplazamiento es la diferencia entre el centro del área visible y el
/// centro del viewport completo. Valores negativos suben el punto.
/// Coordenada vertical de `Alignment` (-1 arriba, 1 abajo) del centro del área
/// visible. Sirve para colocar un cuadro centrado en la parte libre del mapa.
double visibleAreaCenterAlignmentY({
  required double viewportHeight,
  required double topInset,
  required double bottomOccludedHeight,
}) {
  if (viewportHeight <= 0) return 0;
  final offset = visibleAreaCenterOffset(
    viewportHeight: viewportHeight,
    topInset: topInset,
    bottomOccludedHeight: bottomOccludedHeight,
  );
  return (offset.dy / (viewportHeight / 2)).clamp(-1.0, 1.0).toDouble();
}

Offset visibleAreaCenterOffset({
  required double viewportHeight,
  required double topInset,
  required double bottomOccludedHeight,
}) {
  if (viewportHeight <= 0) return Offset.zero;
  final visibleTop = topInset.clamp(0.0, viewportHeight).toDouble();
  final visibleBottom = (viewportHeight - bottomOccludedHeight)
      .clamp(visibleTop, viewportHeight)
      .toDouble();
  final targetY = (visibleTop + visibleBottom) / 2;
  return Offset(0, targetY - viewportHeight / 2);
}

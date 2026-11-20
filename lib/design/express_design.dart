import 'package:flutter/material.dart';

/// Sistema de diseño de Express (rediseño 2026-11).
///
/// Un solo azul de marca, un ámbar reservado para precio y ofertas, tarjetas
/// blancas sobre fondo gris azulado, radios de 16 y 28 px y objetivos táctiles
/// de al menos 48 px. Las pantallas lo consumen desde aquí en lugar de repetir
/// colores sueltos.
abstract final class ExpressDesign {
  // Colores
  static const Color blue = Color(0xFF0B57D0);
  static const Color blueSoft = Color(0xFFE3EDFD);
  static const Color blueTint = Color(0xFFEEF4FE);
  static const Color amber = Color(0xFFFFB020);
  static const Color amberSoft = Color(0xFFFFF1D1);
  static const Color green = Color(0xFF0F8A5F);
  static const Color greenSoft = Color(0xFFE4F4EC);
  static const Color red = Color(0xFFB3261E);
  static const Color redSoft = Color(0xFFFCE9E7);
  static const Color ink = Color(0xFF0E1525);
  static const Color muted = Color(0xFF5B6575);
  static const Color line = Color(0xFFE4E9F2);
  static const Color background = Color(0xFFF4F6FB);

  // Radios
  static const double radiusControl = 16;
  static const double radiusButton = 18;
  static const double radiusCard = 20;
  static const double radiusSheet = 28;

  // Medidas
  static const double minTouch = 48;
  static const double buttonHeight = 56;
  static const double navHeight = 72;

  /// Sombra del panel inferior que se desliza sobre el mapa.
  static const List<BoxShadow> sheetShadow = [
    BoxShadow(
      color: Color(0x24000000),
      blurRadius: 30,
      offset: Offset(0, -8),
    ),
  ];

  /// Cifra de precio: grande y en negrita, la protagonista de la pantalla.
  static TextStyle price({
    double size = 32,
    Color color = ink,
  }) => TextStyle(
    color: color,
    fontSize: size,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.05,
  );
}

/// Aplica los componentes del rediseño sobre un tema base.
///
/// Conserva el esquema de color y las transiciones del tema recibido y solo
/// ajusta formas y alturas de botones, diálogos, paneles y barra inferior.
ThemeData applyExpressDesign(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(ExpressDesign.radiusButton),
  );
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, ExpressDesign.minTouch),
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, ExpressDesign.minTouch),
        shape: shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ExpressDesign.radiusSheet),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ExpressDesign.radiusSheet),
        ),
      ),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      height: ExpressDesign.navHeight,
      indicatorColor: dark
          ? ExpressDesign.blue.withValues(alpha: .28)
          : ExpressDesign.blueSoft,
    ),
  );
}

/// Asa que indica que el panel inferior se puede arrastrar.
class ExpressSheetHandle extends StatelessWidget {
  final bool dark;

  const ExpressSheetHandle({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF3A3A3A) : const Color(0xFFC7D0DE),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

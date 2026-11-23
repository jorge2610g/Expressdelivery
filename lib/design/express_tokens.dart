import 'package:flutter/material.dart';

/// Rediseño Express · tokens de diseño.
///
/// Cinco colores con significado y una rejilla de 4 px:
/// azul = acción principal y precio fijo, ámbar = oferta, menta = en línea y
/// pagado, coral = cancelar, error y SOS. Todo texto cumple contraste 4,5:1.
abstract final class ExpressColors {
  static const ground = Color(0xFF0C111B);
  static const mapGround = Color(0xFF0E1525);
  static const surface = Color(0xFF111827);
  static const card = Color(0xFF151C2B);
  static const raised = Color(0xFF1D2740);
  static const border = Color(0xFF232E4A);
  static const borderStrong = Color(0xFF2B3656);

  static const blue = Color(0xFF3B6CFF);
  static const blueInk = Color(0xFF152048);
  static const blueSoft = Color(0xFF8FB0FF);
  static const blueText = Color(0xFFBFD0FF);

  static const amber = Color(0xFFFFB84D);
  static const amberInk = Color(0xFF3A2C14);

  static const mint = Color(0xFF34D399);
  static const mintInk = Color(0xFF12392F);
  static const mintOn = Color(0xFF06281E);

  static const coral = Color(0xFFF87171);
  static const coralInk = Color(0xFF3A1D22);
  static const coralLine = Color(0xFF4A2A33);

  static const text = Color(0xFFF4F6FB);
  static const textSoft = Color(0xFFB4BED3);
  static const textMuted = Color(0xFF9AA6BF);
  static const textFaint = Color(0xFF7F8CA8);
}

/// Medidas (múltiplos de 4).
abstract final class ExpressSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double touch = 44; // alto mínimo de un control
}

abstract final class ExpressRadii {
  static const double sheet = 28;
  static const double card = 18;
  static const double control = 16;
  static const double pill = 99;
}

/// Tipografía: una sola familia. `family` null usa la del sistema; para la
/// identidad final se incluye Manrope en pubspec y se pasa aquí.
abstract final class ExpressType {
  static String? family;

  static TextStyle _s(double size, FontWeight weight, Color color,
          {double? height, double? letterSpacing}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle get price =>
      _s(40, FontWeight.w800, ExpressColors.text, letterSpacing: -.8);
  static TextStyle get priceSmall =>
      _s(26, FontWeight.w800, ExpressColors.text, letterSpacing: -.3);
  static TextStyle get title =>
      _s(24, FontWeight.w800, ExpressColors.text, letterSpacing: -.3);
  static TextStyle get heading => _s(17, FontWeight.w800, ExpressColors.text);
  static TextStyle get bodyStrong =>
      _s(15, FontWeight.w700, ExpressColors.text);
  static TextStyle get body =>
      _s(15, FontWeight.w500, ExpressColors.textSoft, height: 1.45);
  static TextStyle get caption =>
      _s(12.5, FontWeight.w600, ExpressColors.textMuted, height: 1.4);
  static TextStyle get label => _s(
      12, FontWeight.w700, ExpressColors.textMuted,
      letterSpacing: .96);
}

/// Tema oscuro base de Express.
abstract final class ExpressTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: ExpressColors.blue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: ExpressColors.blue,
      onPrimary: Colors.white,
      surface: ExpressColors.surface,
      onSurface: ExpressColors.text,
      error: ExpressColors.coral,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: ExpressType.family,
      scaffoldBackgroundColor: ExpressColors.ground,
      dividerColor: ExpressColors.border,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: ExpressColors.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

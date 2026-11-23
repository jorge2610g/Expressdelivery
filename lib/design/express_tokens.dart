import 'package:flutter/material.dart';

/// Rediseño Express · tokens de diseño.
///
/// Paleta contenida: grafito neutro y un solo acento. Colores de estado solo en texto y puntos pequeños y una rejilla de 4 px:
/// azul = acción principal y precio fijo, ámbar = oferta, menta = en línea y
/// pagado, coral = cancelar, error y SOS. Todo texto cumple contraste 4,5:1.
abstract final class ExpressColors {
  static const ground = Color(0xFF0B0D12);
  static const mapGround = Color(0xFF0E1117);
  static const surface = Color(0xFF13161D);
  static const card = Color(0xFF181C24);
  static const raised = Color(0xFF1F242E);
  static const border = Color(0xFF262B36);
  static const borderStrong = Color(0xFF323847);

  static const blue = Color(0xFF5B82EE);
  static const blueInk = Color(0xFF1A2130);
  static const blueSoft = Color(0xFF9DB4EA);
  static const blueText = Color(0xFFC6D3F2);

  static const amber = Color(0xFFD9A441);
  static const amberInk = Color(0xFF2A2417);

  static const mint = Color(0xFF4FB58F);
  static const mintInk = Color(0xFF16261F);
  static const mintOn = Color(0xFF0B1A14);

  static const coral = Color(0xFFE0706F);
  static const coralInk = Color(0xFF2A1A1C);
  static const coralLine = Color(0xFF3E2A2D);

  static const text = Color(0xFFF2F4F8);
  static const textSoft = Color(0xFFB3BAC8);
  static const textMuted = Color(0xFF8F97A8);
  static const textFaint = Color(0xFF737B8C);
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
  static const double sheet = 20;
  static const double card = 14;
  static const double control = 12;
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
      _s(40, FontWeight.w700, ExpressColors.text, letterSpacing: -.8);
  static TextStyle get priceSmall =>
      _s(26, FontWeight.w700, ExpressColors.text, letterSpacing: -.3);
  static TextStyle get title =>
      _s(24, FontWeight.w700, ExpressColors.text, letterSpacing: -.3);
  static TextStyle get heading => _s(17, FontWeight.w700, ExpressColors.text);
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
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

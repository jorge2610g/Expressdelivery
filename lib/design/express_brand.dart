import 'package:flutter/material.dart';

/// Colores de marca que ColorScheme no cubre (gradientes de servicio y
/// superficies de accesos rápidos). Se registra en ThemeData.extensions.
@immutable
class ExpressBrandColors extends ThemeExtension<ExpressBrandColors> {
  const ExpressBrandColors({
    required this.rideStart,
    required this.rideEnd,
    required this.parcelStart,
    required this.parcelEnd,
    required this.quickTile,
    required this.quickIconBackground,
    required this.muted,
  });

  final Color rideStart;
  final Color rideEnd;
  final Color parcelStart;
  final Color parcelEnd;
  final Color quickTile;
  final Color quickIconBackground;
  final Color muted;

  static const ExpressBrandColors dark = ExpressBrandColors(
    rideStart: Color(0xFF2F6BFF),
    rideEnd: Color(0xFF5B9BFF),
    parcelStart: Color(0xFFE8914A),
    parcelEnd: Color(0xFFF5B25A),
    quickTile: Color(0xFF1E2636),
    quickIconBackground: Color(0xFFEAF2FF),
    muted: Color(0xFF98A2B3),
  );

  static const ExpressBrandColors light = ExpressBrandColors(
    rideStart: Color(0xFF0B57D0),
    rideEnd: Color(0xFF3B82F6),
    parcelStart: Color(0xFFE08A3C),
    parcelEnd: Color(0xFFF2B05E),
    quickTile: Color(0xFFFFFFFF),
    quickIconBackground: Color(0xFFE7EFFC),
    muted: Color(0xFF667085),
  );

  @override
  ExpressBrandColors copyWith({
    Color? rideStart,
    Color? rideEnd,
    Color? parcelStart,
    Color? parcelEnd,
    Color? quickTile,
    Color? quickIconBackground,
    Color? muted,
  }) {
    return ExpressBrandColors(
      rideStart: rideStart ?? this.rideStart,
      rideEnd: rideEnd ?? this.rideEnd,
      parcelStart: parcelStart ?? this.parcelStart,
      parcelEnd: parcelEnd ?? this.parcelEnd,
      quickTile: quickTile ?? this.quickTile,
      quickIconBackground: quickIconBackground ?? this.quickIconBackground,
      muted: muted ?? this.muted,
    );
  }

  @override
  ExpressBrandColors lerp(
    covariant ThemeExtension<ExpressBrandColors>? other,
    double t,
  ) {
    if (other is! ExpressBrandColors) return this;
    return ExpressBrandColors(
      rideStart: Color.lerp(rideStart, other.rideStart, t)!,
      rideEnd: Color.lerp(rideEnd, other.rideEnd, t)!,
      parcelStart: Color.lerp(parcelStart, other.parcelStart, t)!,
      parcelEnd: Color.lerp(parcelEnd, other.parcelEnd, t)!,
      quickTile: Color.lerp(quickTile, other.quickTile, t)!,
      quickIconBackground:
          Color.lerp(quickIconBackground, other.quickIconBackground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

/// Escala de espaciado: múltiplos de 4.
class ExpressSpace {
  ExpressSpace._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
}

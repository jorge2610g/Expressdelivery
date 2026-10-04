import 'package:flutter/material.dart';

/// Único logotipo oficial de Express dentro de la app.
///
/// El PNG se restaura en CI desde assets/branding/express_app_icon_512.b64
/// y su hash se valida antes de compilar.
class ExpressOfficialLogo extends StatelessWidget {
  final double size;
  final double radius;

  const ExpressOfficialLogo({
    super.key,
    this.size = 48,
    this.radius = 15,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/branding/express_app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

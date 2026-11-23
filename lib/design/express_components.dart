import 'package:flutter/material.dart';

import 'express_tokens.dart';

/// Hoja inferior: esquinas de 28 px, asa visible y contenido que cambia por
/// estado. La tarjeta cambia de contenido, nunca de lugar.
class ExpressSheet extends StatelessWidget {
  const ExpressSheet({
    super.key,
    required this.child,
    this.height,
    this.gap = ExpressSpace.md + 2,
  });

  final Widget child;
  final double? height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: const BoxDecoration(
        color: ExpressColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ExpressRadii.sheet),
        ),
        border: Border(top: BorderSide(color: ExpressColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: ExpressColors.borderStrong,
                borderRadius: BorderRadius.circular(ExpressRadii.pill),
              ),
            ),
          ),
          SizedBox(height: gap),
          Expanded(child: child),
        ],
      ),
    );
  }
}

enum ExpressPriceMode { fixed, offer }

/// Una de las dos tarjetas de precio: «Precio fijo» (azul, candado) y
/// «Ofrece tu precio» (ámbar, flechas). La elegida lleva borde azul grueso,
/// fondo azul tinta, check lleno y la palabra «Elegido»: nunca depende solo
/// del color.
class ExpressPriceCard extends StatelessWidget {
  const ExpressPriceCard({
    super.key,
    required this.mode,
    required this.amount,
    required this.note,
    required this.selected,
    this.onTap,
  });

  final ExpressPriceMode mode;
  final String amount;
  final String note;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fixed = mode == ExpressPriceMode.fixed;
    final title = fixed ? 'Precio fijo' : 'Ofrece tu precio';
    final icon = fixed ? Icons.lock_outline_rounded : Icons.swap_vert_rounded;
    final iconColor = fixed ? ExpressColors.blueSoft : ExpressColors.amber;
    return Semantics(
      button: true,
      selected: selected,
      label: title + (selected ? ', elegido' : ''),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          decoration: BoxDecoration(
            color: selected ? ExpressColors.blueInk : ExpressColors.card,
            borderRadius: BorderRadius.circular(ExpressRadii.card),
            border: Border.all(
              color: selected ? ExpressColors.blue : ExpressColors.border,
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: iconColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ExpressType.bodyStrong.copyWith(fontSize: 13),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: selected
                        ? ExpressColors.blue
                        : ExpressColors.textFaint,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(amount, style: ExpressType.priceSmall),
              const SizedBox(height: 4),
              Text(
                selected ? 'Elegido · $note' : note,
                style: ExpressType.caption.copyWith(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected
                      ? ExpressColors.blueSoft
                      : ExpressColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ExpressButtonKind { primary, outline, danger, success }

/// Botones: alto mínimo 44 px (principal 56). El principal vive en el borde
/// inferior y la salida (cancelar) justo debajo, nunca escondida.
class ExpressButton extends StatelessWidget {
  const ExpressButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ExpressButtonKind.primary,
    this.icon,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final ExpressButtonKind kind;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    Color? line;
    switch (kind) {
      case ExpressButtonKind.primary:
        bg = ExpressColors.blue;
        fg = Colors.white;
      case ExpressButtonKind.success:
        bg = ExpressColors.mint;
        fg = ExpressColors.mintOn;
      case ExpressButtonKind.outline:
        bg = Colors.transparent;
        fg = ExpressColors.blueText;
        line = ExpressColors.blue;
      case ExpressButtonKind.danger:
        bg = Colors.transparent;
        fg = ExpressColors.coral;
        line = ExpressColors.coralLine;
    }
    return SizedBox(
      height: height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(ExpressRadii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(ExpressRadii.card),
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            decoration: line == null
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(ExpressRadii.card),
                    border: Border.all(color: line, width: 1.5),
                  ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: ExpressType.family,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra de tiempo: todo proceso con reloj muestra barra y segundos.
class ExpressCountdownBar extends StatelessWidget {
  const ExpressCountdownBar({
    super.key,
    required this.progress,
    this.color = ExpressColors.blue,
    this.height = 6,
  });

  final double progress;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(ExpressRadii.pill),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: ExpressColors.border,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// Píldora de estado: «En línea», «Buscando 00:42», «Oferta», «Se cancela…».
class ExpressPill extends StatelessWidget {
  const ExpressPill({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(ExpressRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontFamily: ExpressType.family,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fondo de mapa estilizado para las maquetas y pruebas (no es el mapa real).
class ExpressMapBackdrop extends StatelessWidget {
  const ExpressMapBackdrop({
    super.key,
    this.route = true,
    this.routeColor = ExpressColors.blue,
  });

  final bool route;
  final Color routeColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MapPainter(route: route, routeColor: routeColor),
      size: Size.infinite,
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.route, required this.routeColor});
  final bool route;
  final Color routeColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = ExpressColors.mapGround,
    );
    final water = Path()
      ..moveTo(0, 0)
      ..lineTo(130, 0)
      ..lineTo(100, 70)
      ..lineTo(40, 120)
      ..lineTo(0, 170)
      ..close();
    canvas.drawPath(water, Paint()..color = const Color(0xFF0A2236));
    final minor = Paint()
      ..color = const Color(0xFF18233B)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    for (final y in [160.0, 240.0, 320.0, 400.0]) {
      canvas.drawLine(Offset(-10, y), Offset(size.width + 10, y), minor);
    }
    for (final x in [50.0, 130.0, 210.0, 290.0, 370.0]) {
      canvas.drawLine(Offset(x, -10), Offset(x, 440), minor);
    }
    final major = Paint()
      ..color = const Color(0xFF26344F)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-10, 280), Offset(size.width + 10, 220), major);
    canvas.drawLine(const Offset(210, -10), const Offset(250, 440), major);
    if (!route) return;
    final path = Path()
      ..moveTo(130, 350)
      ..lineTo(130, 250)
      ..lineTo(290, 250)
      ..lineTo(290, 130);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF0A1A55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = routeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(const Offset(130, 350), 12, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(130, 350),
      12,
      Paint()
        ..color = ExpressColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawCircle(
        const Offset(290, 130), 17, Paint()..color = ExpressColors.mint);
    final tp = TextPainter(
      text: const TextSpan(
        text: 'B',
        style: TextStyle(
          color: ExpressColors.mintOn,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(290 - tp.width / 2, 130 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.route != route || old.routeColor != routeColor;
}

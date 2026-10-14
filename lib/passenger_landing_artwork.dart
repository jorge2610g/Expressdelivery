import 'package:flutter/material.dart';

/// Lightweight offline vector artwork for the Express landing cards.
/// No remote image download is needed to display the main service menu.
class ExpressLandingArtwork extends StatelessWidget {
  final String kind;
  final double size;
  const ExpressLandingArtwork({
    super.key,
    required this.kind,
    this.size = 142,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * .76,
        child: CustomPaint(
          painter: _ExpressArtworkPainter(kind),
        ),
      );
}

class _ExpressArtworkPainter extends CustomPainter {
  final String kind;
  const _ExpressArtworkPainter(this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 150);

    Paint paint(Color color, {double opacity = 1}) =>
        Paint()..color = color.withValues(alpha: opacity);
    void oval(Rect r, Color color, {double opacity = 1}) =>
        canvas.drawOval(r, paint(color, opacity: opacity));
    void rr(Rect r, double radius, Color color, {double opacity = 1}) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(radius)),
          paint(color, opacity: opacity),
        );
    void path(List<Offset> points, Color color) {
      final p = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        p.lineTo(point.dx, point.dy);
      }
      p.close();
      canvas.drawPath(p, paint(color));
    }

    // Floating highlights and contact shadow make these real illustrations,
    // rather than a single icon floating in an empty square.
    oval(const Rect.fromLTWH(13, 0, 158, 131), Colors.white, opacity: .12);
    oval(const Rect.fromLTWH(40, 126, 142, 16), const Color(0xFF0E2341),
        opacity: .20);
    if (kind == 'ride') {
      // Windshield, tinted roof, body and wheels.
      rr(const Rect.fromLTWH(55, 49, 92, 57), 21,
          const Color(0xFFEAF4FF));
      path([
        const Offset(68, 56), const Offset(83, 36),
        const Offset(128, 37), const Offset(143, 57),
      ], const Color(0xFFF4FAFF));
      rr(const Rect.fromLTWH(83, 43, 42, 24), 7,
          const Color(0xFF80C7EE));
      rr(const Rect.fromLTWH(40, 66, 125, 55), 15,
          const Color(0xFFFCFCFE));
      rr(const Rect.fromLTWH(52, 79, 103, 16), 7,
          const Color(0xFFCCE4FA));
      rr(const Rect.fromLTWH(46, 102, 114, 14), 7,
          const Color(0xFFDAE9FA));
      oval(const Rect.fromLTWH(53, 106, 27, 27),
          const Color(0xFF162B4E));
      oval(const Rect.fromLTWH(129, 106, 27, 27),
          const Color(0xFF162B4E));
      oval(const Rect.fromLTWH(60, 113, 13, 13),
          const Color(0xFF9BAEC8));
      oval(const Rect.fromLTWH(136, 113, 13, 13),
          const Color(0xFF9BAEC8));
      rr(const Rect.fromLTWH(146, 82, 15, 8), 4,
          const Color(0xFFFFC66B));
      rr(const Rect.fromLTWH(40, 82, 15, 8), 4,
          const Color(0xFFFFC66B));
    } else if (kind == 'delivery') {
      // Package stack with side panels and warm shipping tape.
      rr(const Rect.fromLTWH(38, 80, 91, 53), 8,
          const Color(0xFFFFE5AA));
      rr(const Rect.fromLTWH(43, 86, 81, 46), 5,
          const Color(0xFFF8C36B));
      path([
        const Offset(85, 86), const Offset(125, 86),
        const Offset(124, 128), const Offset(85, 131),
      ], const Color(0xFFEBA34B));
      rr(const Rect.fromLTWH(75, 85, 15, 44), 3,
          const Color(0xFFFFF0D0));
      rr(const Rect.fromLTWH(103, 48, 73, 51), 7,
          const Color(0xFFFFF0CB));
      rr(const Rect.fromLTWH(108, 53, 62, 44), 5,
          const Color(0xFFE8B875));
      path([
        const Offset(139, 53), const Offset(170, 53),
        const Offset(170, 97), const Offset(139, 97),
      ], const Color(0xFFD8A15F));
      rr(const Rect.fromLTWH(131, 53, 14, 36), 2,
          const Color(0xFFFFF1D8));
      rr(const Rect.fromLTWH(118, 111, 26, 5), 2,
          const Color(0xFF985A27));
    } else {
      // Grocery bag with fruit and fresh produce for Express Market.
      path([
        const Offset(49, 64), const Offset(159, 64),
        const Offset(148, 135), const Offset(62, 135),
      ], const Color(0xFFFFE4A6));
      path([
        const Offset(49, 64), const Offset(103, 74),
        const Offset(107, 136), const Offset(62, 135),
      ], const Color(0xFFF2BE62));
      oval(const Rect.fromLTWH(56, 31, 55, 56),
          const Color(0xFFF87148));
      oval(const Rect.fromLTWH(91, 29, 51, 51),
          const Color(0xFFFFCA62));
      oval(const Rect.fromLTWH(110, 39, 48, 48),
          const Color(0xFF6FC77D));
      path([
        const Offset(74, 31), const Offset(65, 18),
        const Offset(89, 24),
      ], const Color(0xFF3FA667));
      rr(const Rect.fromLTWH(94, 67, 15, 20), 7,
          const Color(0xFFFFF6E5));
      rr(const Rect.fromLTWH(87, 91, 40, 6), 3,
          const Color(0xFFBC8745));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ExpressArtworkPainter oldDelegate) =>
      oldDelegate.kind != kind;
}

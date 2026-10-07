import 'package:flutter/material.dart';

/// Shared motion language for Express.
///
/// Keep product state, backend work and GPS independent from animation. Motion
/// only explains a state change that already happened (or is happening) and
/// automatically collapses when the operating system asks to reduce motion.
abstract final class ExpressMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration emphasis = Duration(milliseconds: 360);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
  static const Curve incoming = Curves.easeOutBack;

  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration duration(
    BuildContext context, [
    Duration preferred = normal,
  ]) =>
      reduceMotion(context) ? Duration.zero : preferred;
}

/// Gentle first-paint animation for cards, forms and meaningful sections.
class ExpressMotionEntrance extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final double verticalOffset;
  final double beginScale;
  final Curve curve;

  const ExpressMotionEntrance({
    super.key,
    required this.child,
    this.duration = ExpressMotion.normal,
    this.verticalOffset = 14,
    this.beginScale = .985,
    this.curve = ExpressMotion.standard,
  });

  @override
  Widget build(BuildContext context) {
    if (ExpressMotion.reduceMotion(context)) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      child: child,
      builder: (context, value, child) {
        final dy = (1 - value) * verticalOffset;
        final scale = beginScale + ((1 - beginScale) * value);
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Animated replacement used for auth modes, onboarding steps and status
/// changes. The outgoing element fades/slides slightly while the new element
/// arrives, avoiding the visual "cut" of a raw rebuild.
class ExpressMotionSwap extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Offset incomingOffset;
  final double incomingScale;
  final Alignment alignment;

  const ExpressMotionSwap({
    super.key,
    required this.child,
    this.duration = ExpressMotion.normal,
    this.incomingOffset = const Offset(0, .035),
    this.incomingScale = .99,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final reduced = ExpressMotion.reduceMotion(context);

    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : duration,
      reverseDuration:
          reduced ? Duration.zero : const Duration(milliseconds: 180),
      switchInCurve: ExpressMotion.emphasized,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: alignment,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        if (reduced) return child;
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        final slide = Tween<Offset>(
          begin: incomingOffset,
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: ExpressMotion.standard,
          ),
        );
        final scale = Tween<double>(
          begin: incomingScale,
          end: 1,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: ExpressMotion.emphasized,
          ),
        );

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
              alignment: alignment,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// Lightweight animated progress bar used by multi-step Express flows.
class ExpressMotionProgress extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Color? backgroundColor;

  const ExpressMotionProgress({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    final foreground = color ?? scheme.primary;
    final background =
        backgroundColor ?? scheme.primary.withValues(alpha: .12);
    final reduced = ExpressMotion.reduceMotion(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: clamped),
        duration: reduced ? Duration.zero : ExpressMotion.emphasis,
        curve: ExpressMotion.emphasized,
        builder: (context, animatedValue, _) => LinearProgressIndicator(
          value: animatedValue,
          minHeight: height,
          backgroundColor: background,
          valueColor: AlwaysStoppedAnimation<Color>(foreground),
        ),
      ),
    );
  }
}

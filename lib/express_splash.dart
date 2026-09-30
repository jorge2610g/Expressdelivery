import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class ExpressLaunchGate extends StatefulWidget {
  final Widget child;
  final Duration minimumDuration;

  const ExpressLaunchGate({
    super.key,
    required this.child,
    this.minimumDuration = const Duration(milliseconds: 1350),
  });

  @override
  State<ExpressLaunchGate> createState() => _ExpressLaunchGateState();
}

class _ExpressLaunchGateState extends State<ExpressLaunchGate> {
  Timer? timer;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    timer = Timer(widget.minimumDuration, () {
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: ready,
          child: AnimatedOpacity(
            opacity: ready ? 0 : 1,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            child: const ExpressSplashPage(),
          ),
        ),
      ],
    );
  }
}

class ExpressSplashPage extends StatefulWidget {
  const ExpressSplashPage({super.key});

  @override
  State<ExpressSplashPage> createState() => _ExpressSplashPageState();
}

class _ExpressSplashPageState extends State<ExpressSplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> markScale;
  late final Animation<double> markOpacity;
  late final Animation<double> wordOpacity;
  late final Animation<Offset> wordSlide;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    )..forward();

    markScale = Tween<double>(begin: .62, end: 1).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0, .48, curve: Curves.easeOutBack),
      ),
    );
    markOpacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(0, .28, curve: Curves.easeOut),
    );
    wordOpacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(.20, .62, curve: Curves.easeOut),
    );
    wordSlide = Tween<Offset>(
      begin: const Offset(.30, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(.18, .68, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF07111F),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.08),
            radius: 1.05,
            colors: [
              Color(0xFF123C73),
              Color(0xFF09192B),
              Color(0xFF050B14),
            ],
            stops: [0, .48, 1],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final pulse = .5 + .5 * math.sin(controller.value * math.pi * 2);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: markOpacity,
                    child: ScaleTransition(
                      scale: markScale,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF36A6FF),
                              Color(0xFF0B57D0),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1596FF).withValues(
                                alpha: .20 + pulse * .18,
                              ),
                              blurRadius: 26 + pulse * 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  FadeTransition(
                    opacity: wordOpacity,
                    child: SlideTransition(
                      position: wordSlide,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Express',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              height: .95,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.5,
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            'VIAJES · DELIVERY',
                            style: TextStyle(
                              color: Color(0xFFAED6FF),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

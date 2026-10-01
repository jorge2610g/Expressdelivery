import 'dart:async';

import 'package:flutter/material.dart';

class ExpressLaunchGate extends StatefulWidget {
  final Widget child;
  final Duration minimumDuration;

  const ExpressLaunchGate({
    super.key,
    required this.child,
    this.minimumDuration = const Duration(milliseconds: 1550),
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
            duration: const Duration(milliseconds: 320),
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
  late final Animation<double> markOpacity;
  late final Animation<double> markScale;
  late final Animation<double> textOpacity;
  late final Animation<Offset> textSlide;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    markOpacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(0, .32, curve: Curves.easeOut),
    );
    markScale = Tween<double>(begin: .88, end: 1).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0, .48, curve: Curves.easeOutCubic),
      ),
    );
    textOpacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(.20, .62, curve: Curves.easeOut),
    );
    textSlide = Tween<Offset>(
      begin: const Offset(0, .12),
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
      color: Colors.white,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFF8FBFF),
              Color(0xFFF0F6FF),
            ],
            stops: [0, .62, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 650;
              final logoSize = compact ? 152.0 : 184.0;

              return Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned(
                    left: -65,
                    bottom: -95,
                    child: _SplashOrb(
                      size: 245,
                      color: Color(0x120B57D0),
                    ),
                  ),
                  const Positioned(
                    right: -54,
                    top: 70,
                    child: _SplashOrb(
                      size: 170,
                      color: Color(0x0D39A0FF),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FadeTransition(
                            opacity: markOpacity,
                            child: ScaleTransition(
                              scale: markScale,
                              child: Container(
                                width: logoSize,
                                height: logoSize,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(34),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x160B57D0),
                                      blurRadius: 34,
                                      offset: Offset(0, 14),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.asset(
                                  'assets/branding/express_app_icon.png',
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 22 : 28),
                          FadeTransition(
                            opacity: textOpacity,
                            child: SlideTransition(
                              position: textSlide,
                              child: const Column(
                                children: [
                                  Text(
                                    'Express Delivery',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF0A2351),
                                      fontSize: 34,
                                      height: 1,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.1,
                                    ),
                                  ),
                                  SizedBox(height: 11),
                                  Text(
                                    'Rápido. Seguro. Para todos.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF667085),
                                      fontSize: 14,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: .15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 42,
                    right: 42,
                    bottom: compact ? 30 : 42,
                    child: FadeTransition(
                      opacity: textOpacity,
                      child: const _SplashProgress(),
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

class _SplashOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _SplashOrb({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _SplashProgress extends StatelessWidget {
  const _SplashProgress();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 116,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFFDDE8F8),
          borderRadius: BorderRadius.circular(99),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: .56,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0B57D0),
                  Color(0xFF39A0FF),
                ],
              ),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// The passenger home grows with its content and scrolls only on short screens.
class PassengerContentSheet extends StatelessWidget {
  final Widget child;
  const PassengerContentSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: AnimatedSize(
      duration: const Duration(milliseconds: 240),
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: SingleChildScrollView(
          primary: false,
          physics: const ClampingScrollPhysics(),
          child: child,
        ),
      ),
    ),
  );
}

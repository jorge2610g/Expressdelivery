import 'package:flutter/material.dart';

/// Express-branded, responsive dialog for important trip decisions.
///
/// Keeps the action logic in the caller and only improves the presentation.
/// Long translations, larger accessibility fonts and small Android screens
/// scroll instead of overflowing the viewport.
class ExpressJourneyDialog extends StatelessWidget {
  const ExpressJourneyDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.content,
    required this.actions,
    this.semanticLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget content;
  final List<Widget> actions;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const blue = Color(0xFF0B57D0);
    final viewportHeight = MediaQuery.sizeOf(context).height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      backgroundColor: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: viewportHeight * .86,
        ),
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: semanticLabel ?? title,
                child: Container(
                  height: 62,
                  width: 62,
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, color: blue, size: 30),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              content,
              const SizedBox(height: 18),
              ...[
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: actions[i]),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Horizontal cards retain their own content height instead of a fixed viewport.
class ContentSizedHorizontalList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  const ContentSizedHorizontalList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          if (i > 0)
            separatorBuilder?.call(context, i - 1) ?? const SizedBox(width: 12),
          itemBuilder(context, i),
        ],
      ],
    ),
  );
}

/// Fixed column widths, natural card heights, including enlarged system text.
class ContentSizedGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double spacing;
  const ContentSizedGrid({
    super.key,
    required this.children,
    this.columns = 2,
    this.spacing = 10,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = (bounds.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

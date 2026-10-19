import 'package:flutter/material.dart';

/// Below this width pages switch to their phone layout.
const compactWidth = 600.0;

bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < compactWidth;

/// Page gutter: tighter on phones so content keeps most of the width.
EdgeInsets pagePadding(BuildContext context, {double top = 20, double bottom = 0}) {
  final side = isCompact(context) ? 12.0 : 24.0;
  return EdgeInsets.fromLTRB(side, isCompact(context) ? 12 : top, side, bottom);
}

/// Title (plus an optional badge) on the left, actions on the right. When
/// the row does not fit, the actions drop to the next line instead of
/// overflowing.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.badge, this.actions = const []});

  final String title;
  final Widget? badge;
  final List<Widget> actions;

  @override
  // Full width even inside a start-aligned Column, so spaceBetween pushes
  // the actions to the right edge.
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (badge != null) ...[const SizedBox(width: 12), badge!],
          ],
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
      ],
    ),
  );
}

/// Quiet count next to a page title ("5,445 trips"); a Chip reads as a
/// button.
class CountPill extends StatelessWidget {
  const CountPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
    );
  }
}

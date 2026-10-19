import 'package:flutter/material.dart';

import '../brand_font.dart';
import '../theme.dart';

/// The "badrgo" wordmark in brand red (or [color]), optionally followed by a
/// product name such as "Ops".
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 24, this.suffix, this.color});

  final double size;
  final String? suffix;

  /// Overrides the brand red, e.g. white on the red sign-in panel.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final mark = color ?? AppTheme.brandRed;
    final suffixColor = color?.withValues(alpha: 0.8) ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'badrgo',
            style: TextStyle(color: mark, fontWeight: FontWeight.w600, letterSpacing: -0.5),
          ),
          if (suffix != null)
            TextSpan(
              text: ' $suffix',
              style: TextStyle(color: suffixColor, fontWeight: FontWeight.w500),
            ),
        ],
      ),
      style: TextStyle(fontFamily: BrandFont.family, fontSize: size, height: 1),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../brand_font.dart';
import '../theme.dart';

/// The official badrgo logo (with its "Your way to go" tagline), optionally
/// followed by a product name such as "Ops".
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.height = 36, this.suffix, this.color});

  static const asset = 'assets/brand/badrgo_logo.svg';

  /// Height of the logo, tagline included.
  final double height;
  final String? suffix;

  /// Recolours the logo, e.g. white on the red sign-in panel. Defaults to the
  /// brand red.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final logo = SvgPicture.asset(
      asset,
      height: height,
      semanticsLabel: 'badrgo',
      // The tint is applied explicitly so the logo is brand red (or white)
      // whatever the SVG's own styling support is.
      colorFilter: ColorFilter.mode(color ?? AppTheme.brandRed, BlendMode.srcIn),
    );
    if (suffix == null) return logo;
    final suffixColor = color?.withValues(alpha: 0.85) ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        SizedBox(width: height * 0.15),
        // The logo's letters sit in its upper two thirds; lift the suffix to
        // line up with them rather than with the tagline.
        Padding(
          padding: EdgeInsets.only(bottom: height * 0.22),
          child: Text(
            suffix!,
            style: TextStyle(
              fontFamily: BrandFont.family,
              fontSize: height * 0.5,
              fontWeight: FontWeight.w500,
              height: 1,
              color: suffixColor,
            ),
          ),
        ),
      ],
    );
  }
}

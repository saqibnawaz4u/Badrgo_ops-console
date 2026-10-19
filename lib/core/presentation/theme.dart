import 'package:flutter/material.dart';

import 'brand_font.dart';

/// Semantic colours used across the console (status chips, map markers,
/// banners), tuned per brightness.
class OpsColors extends ThemeExtension<OpsColors> {
  const OpsColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.neutral,
    required this.created,
    required this.updated,
    required this.progress,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color neutral;

  /// Row highlights for live list changes.
  final Color created;
  final Color updated;

  /// Trips in progress: distinct from the brand red, which reads as an error.
  final Color progress;

  static const light = OpsColors(
    success: Color(0xFF1E8E3E),
    warning: Color(0xFFB26A00),
    danger: Color(0xFFC5221F),
    info: Color(0xFF1A73E8),
    neutral: Color(0xFF6B7280),
    created: Color(0xFFE6F4EA),
    updated: Color(0xFFFFF4D6),
    progress: Color(0xFF6D28D9),
  );

  static const dark = OpsColors(
    success: Color(0xFF81C995),
    warning: Color(0xFFFDD663),
    danger: Color(0xFFF28B82),
    info: Color(0xFF8AB4F8),
    neutral: Color(0xFF9CA3AF),
    created: Color(0xFF1E3A2A),
    updated: Color(0xFF3D3420),
    progress: Color(0xFFC4B5FD),
  );

  static OpsColors of(BuildContext context) => Theme.of(context).extension<OpsColors>()!;

  @override
  OpsColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? neutral,
    Color? created,
    Color? updated,
    Color? progress,
  }) => OpsColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    info: info ?? this.info,
    neutral: neutral ?? this.neutral,
    created: created ?? this.created,
    updated: updated ?? this.updated,
    progress: progress ?? this.progress,
  );

  /// Per-field blend so a light/dark switch animates instead of snapping.
  @override
  OpsColors lerp(OpsColors? other, double t) {
    if (other == null) return this;
    return OpsColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      created: Color.lerp(created, other.created, t)!,
      updated: Color.lerp(updated, other.updated, t)!,
      progress: Color.lerp(progress, other.progress, t)!,
    );
  }
}

class AppTheme {
  const AppTheme._();

  /// badrgo's brand red, as used on badrgo.com.
  static const brandRed = Color(0xFFCF1B1C);

  static ThemeData light() => _build(Brightness.light, OpsColors.light);

  static ThemeData dark() => _build(Brightness.dark, OpsColors.dark);

  static ThemeData _build(Brightness brightness, OpsColors ops) {
    final isLight = brightness == Brightness.light;
    // Fidelity keeps the generated primary close to the brand red; light
    // mode uses the exact brand colour for buttons and selection.
    final generated = ColorScheme.fromSeed(
      seedColor: brandRed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    // Neutral roles (text, outlines, surfaces) come from a grey seed, so the
    // red only shows where the brand belongs and text does not turn brown.
    final neutral = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5F6368),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    final tint = isLight ? const Color(0xFFFDECEC) : const Color(0xFF4A1616);
    final scheme = generated.copyWith(
      primary: isLight ? brandRed : generated.primary,
      onPrimary: isLight ? Colors.white : generated.onPrimary,
      // Soft brand tint for selected states (navigation, segmented buttons).
      primaryContainer: tint,
      onPrimaryContainer: isLight ? brandRed : generated.onPrimaryContainer,
      secondaryContainer: tint,
      onSecondaryContainer: isLight ? brandRed : generated.onSecondaryContainer,
      surface: neutral.surface,
      onSurface: neutral.onSurface,
      onSurfaceVariant: neutral.onSurfaceVariant,
      surfaceContainerLowest: neutral.surfaceContainerLowest,
      surfaceContainerLow: neutral.surfaceContainerLow,
      surfaceContainer: neutral.surfaceContainer,
      surfaceContainerHigh: neutral.surfaceContainerHigh,
      surfaceContainerHighest: neutral.surfaceContainerHighest,
      outline: neutral.outline,
      outlineVariant: neutral.outlineVariant,
      inverseSurface: neutral.inverseSurface,
      onInverseSurface: neutral.onInverseSurface,
    );
    // Panels (cards, top bar, navigation) sit on one flat surface without
    // Material's tint, separated from the page by hairline borders.
    final panel = isLight ? Colors.white : scheme.surfaceContainerLow;
    final hairline = scheme.outlineVariant.withValues(alpha: isLight ? 0.7 : 0.5);
    final text = ThemeData(useMaterial3: true, colorScheme: scheme).textTheme;
    // Headings use the brand typeface; body text stays on the default font,
    // which reads better in dense tables.
    TextStyle? heading(TextStyle? style, {double letterSpacing = -0.2}) =>
        style?.copyWith(fontFamily: BrandFont.family, fontWeight: FontWeight.w600, letterSpacing: letterSpacing);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [ops],
      scaffoldBackgroundColor: isLight ? const Color(0xFFF5F5F6) : scheme.surface,
      textTheme: text.copyWith(
        displaySmall: heading(text.displaySmall, letterSpacing: -0.8),
        headlineMedium: heading(text.headlineMedium, letterSpacing: -0.5),
        headlineSmall: heading(text.headlineSmall, letterSpacing: -0.4),
        titleLarge: heading(text.titleLarge),
        titleMedium: heading(text.titleMedium, letterSpacing: 0),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: hairline)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: panel,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        selectedLabelTextStyle: text.labelLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: panel, surfaceTintColor: Colors.transparent),
      dividerTheme: DividerThemeData(color: hairline, space: 1),
      cardTheme: CardThemeData(
        color: panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        isDense: true,
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(color: panel, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: panel, surfaceTintColor: Colors.transparent),
      visualDensity: VisualDensity.standard,
    );
  }
}

import 'package:flutter/material.dart';

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
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color neutral;

  /// Row highlights for live list changes.
  final Color created;
  final Color updated;

  static const light = OpsColors(
    success: Color(0xFF1E8E3E),
    warning: Color(0xFFB26A00),
    danger: Color(0xFFC5221F),
    info: Color(0xFF1A73E8),
    neutral: Color(0xFF6B7280),
    created: Color(0xFFE6F4EA),
    updated: Color(0xFFFFF4D6),
  );

  static const dark = OpsColors(
    success: Color(0xFF81C995),
    warning: Color(0xFFFDD663),
    danger: Color(0xFFF28B82),
    info: Color(0xFF8AB4F8),
    neutral: Color(0xFF9CA3AF),
    created: Color(0xFF1E3A2A),
    updated: Color(0xFF3D3420),
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
  }) =>
      OpsColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        info: info ?? this.info,
        neutral: neutral ?? this.neutral,
        created: created ?? this.created,
        updated: updated ?? this.updated,
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
    );
  }
}

class AppTheme {
  const AppTheme._();

  static const _seed = Color(0xFF0B6E69);

  static ThemeData light() => _build(Brightness.light, OpsColors.light);

  static ThemeData dark() => _build(Brightness.dark, OpsColors.dark);

  static ThemeData _build(Brightness brightness, OpsColors ops) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final isLight = brightness == Brightness.light;
    // Panels (cards, top bar, navigation) sit on one flat surface without
    // Material's tint, separated from the page by hairline borders.
    final panel = isLight ? Colors.white : scheme.surfaceContainerLow;
    final hairline = scheme.outlineVariant.withValues(alpha: isLight ? 0.7 : 0.5);
    final text = ThemeData(useMaterial3: true, colorScheme: scheme).textTheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [ops],
      scaffoldBackgroundColor: isLight ? const Color(0xFFF3F5F7) : scheme.surface,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
          borderRadius: BorderRadius.circular(12),
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

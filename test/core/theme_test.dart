import 'package:badrgo_ops_console/core/presentation/theme.dart';
import 'package:badrgo_ops_console/core/presentation/theme_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('OpsColors.lerp', () {
    test('the midpoint is a blend, not either end', () {
      final mid = OpsColors.light.lerp(OpsColors.dark, 0.5);

      expect(mid.success, isNot(OpsColors.light.success));
      expect(mid.success, isNot(OpsColors.dark.success));
      expect(mid.updated, Color.lerp(OpsColors.light.updated, OpsColors.dark.updated, 0.5));
    });

    test('the ends are exact', () {
      expect(OpsColors.light.lerp(OpsColors.dark, 0).danger, OpsColors.light.danger);
      expect(OpsColors.light.lerp(OpsColors.dark, 1).danger, OpsColors.dark.danger);
    });
  });

  test('OpsColors.copyWith replaces only the given fields', () {
    final copy = OpsColors.light.copyWith(info: Colors.pink);

    expect(copy.info, Colors.pink);
    expect(copy.success, OpsColors.light.success);
  });

  test('ThemeCubit.setMode can go back to system and persists it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cubit = ThemeCubit(prefs)..toggle(Brightness.light);
    expect(cubit.state, ThemeMode.dark);

    cubit.setMode(ThemeMode.system);
    expect(cubit.state, ThemeMode.system);
    expect(ThemeCubit(prefs).state, ThemeMode.system);
    await cubit.close();
  });
}

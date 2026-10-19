import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light / dark / system, remembered across reloads.
class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit(this._prefs) : super(_read(_prefs));

  static const _key = 'badrgo.theme_mode';
  final SharedPreferences _prefs;

  static ThemeMode _read(SharedPreferences prefs) =>
      ThemeMode.values.where((m) => m.name == prefs.getString(_key)).firstOrNull ?? ThemeMode.system;

  void toggle(Brightness current) =>
      setMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  /// Also the only way back to [ThemeMode.system] after a toggle.
  void setMode(ThemeMode mode) {
    _prefs.setString(_key, mode.name);
    emit(mode);
  }
}
